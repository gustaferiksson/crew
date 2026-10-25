import importlib.util
import json
import subprocess
import sys
import textwrap
import time
import types
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from conftest import CARD, PLUGIN_ROOT, Vaults, fixture
from crew_push import payments, store

R = "5f0c3e9a2b7d4c18a6e1f20b9d3c7a54"
API = "/api/plugins/crew-push"


@pytest.fixture
def app(plugin_api: types.ModuleType, monkeypatch: pytest.MonkeyPatch) -> FastAPI:
    monkeypatch.setitem(sys.modules, "hermes_yaml", types.SimpleNamespace(safe_load=json.loads))
    app = FastAPI()
    app.state.auth_required = True
    app.include_router(plugin_api.router, prefix=API)
    return app


@pytest.fixture
def client(app: FastAPI) -> TestClient:
    return TestClient(app)


@pytest.fixture
def master(vaults: Vaults, hermes_root: Path) -> Path:
    vaults.add(hermes_root / "vault" / "crew-push", "payment", "Shopping card", CARD)
    return hermes_root / "vault" / "crew-push"


def scout_vault(hermes_root: Path) -> Path:
    return hermes_root / "profiles" / "scout" / "vault"


def add_shop(client: TestClient, site: str = "https://www.zalando.se/checkout?step=2", profile: str = "scout"):
    return client.post(f"{API}/payments/shops", json={"profile": profile, "site": site})


def test_status_reports_payments_and_the_gate(client: TestClient, app: FastAPI) -> None:
    assert store.read_gate() is None
    body = client.get(f"{API}/status").json()
    assert body["features"] == ["payments", "card", "card_vault"] and body["gate"] is True
    app.state.auth_required = False
    assert client.get(f"{API}/status").json()["gate"] is False
    expected = fixture("status.json")
    assert set(body) == set(expected)


def test_gate_is_read_from_gate_json_in_a_fresh_process(client: TestClient, hermes_root: Path) -> None:
    client.get(f"{API}/status")
    script = textwrap.dedent(f"""
        import sys, types
        sys.modules["hermes_constants"] = types.SimpleNamespace(get_default_hermes_root=lambda: {str(hermes_root)!r})
        sys.path.insert(0, {str(PLUGIN_ROOT)!r})
        from crew_push import store
        print(store.read_gate())
    """)
    run = subprocess.run([sys.executable, "-c", script], capture_output=True, text=True, timeout=30)
    assert run.stdout.strip() == "True", run.stderr
    gate = json.loads((hermes_root / "plugin-data" / "crew-push" / "gate.json").read_text())
    assert gate["auth_required"] is True and abs(gate["seen_at"] - time.time()) < 60


def test_payments_lists_the_card_and_shops(client: TestClient, master: Path, vaults: Vaults, hermes_root: Path) -> None:
    vaults.next_ids.append("vault_3f9a1c2b7d4e")
    assert add_shop(client).status_code == 201
    vaults.add(scout_vault(hermes_root), "login", "Zalando login", {"password": "x"}, "https://www.zalando.se")
    store.mutate_payments(lambda entries: [
        {"request_id": "a" * 32, "profile": "scout", "origin": "https://www.zalando.se", "state": "approved",
         "decided_at": 1760610000.0},
        {"request_id": "b" * 32, "profile": "scout", "origin": "https://www.zalando.se", "state": "denied",
         "decided_at": 1760620000.0},
        {"request_id": "c" * 32, "profile": "other", "origin": "https://www.zalando.se", "state": "approved",
         "decided_at": 1760630000.0}])
    response = client.get(f"{API}/payments", params={"bot": "scout"})
    assert response.status_code == 200
    assert response.json() == fixture("payments.json")
    assert "4242 4242" not in response.text


def test_payments_without_a_master(client: TestClient, vaults: Vaults) -> None:
    assert client.get(f"{API}/payments", params={"bot": "scout"}).json() == fixture("payments-no-card.json")


def test_payments_with_several_masters(client: TestClient, app: FastAPI, master: Path,
                                                      vaults: Vaults, hermes_root: Path) -> None:
    vaults.next_ids.append("vault_3f9a1c2b7d4e")
    add_shop(client)
    vaults.add(master, "payment", "Old card", {**CARD, "card_number": "5555555555554444"})
    (hermes_root / "profiles" / "scout" / "config.yaml").write_text('{"terminal": {"backend": "docker"}}')
    store.mutate_payments(lambda entries: [{"request_id": "a" * 32, "profile": "scout", "state": "approved",
                                            "origin": "https://www.zalando.se", "decided_at": 1760610000.0}])
    app.state.auth_required = False
    assert client.get(f"{API}/payments", params={"bot": "scout"}).json() == fixture("payments-several.json")


def test_payments_flags_a_code_that_does_not_fit_the_card(client: TestClient, vaults: Vaults, hermes_root: Path,
                                                          caplog: pytest.LogCaptureFixture) -> None:
    caplog.set_level("DEBUG")
    vaults.add(hermes_root / "vault" / "crew-push", "payment", "Shopping card",
               {**CARD, "card_number": "5555 5555 5555 4444", "cvc": "1234"})
    response = client.get(f"{API}/payments", params={"bot": "scout"})
    assert response.json() == fixture("payments-code-mismatch.json")
    assert "1234" not in response.text and "1234" not in caplog.text


@pytest.mark.parametrize(("number", "cvc", "mismatch"), [
    ("4242424242424242", "123", False),
    ("3782 822463 10005", "1234", False),
    ("378282246310005", "123", True),
    ("4242424242424242", "12a", True),
])
def test_code_length_follows_the_card_brand(client: TestClient, vaults: Vaults, hermes_root: Path, number: str,
                                            cvc: str, mismatch: bool) -> None:
    vaults.add(hermes_root / "vault" / "crew-push", "payment", "Shopping card",
               {**CARD, "card_number": number, "cvc": cvc})
    assert client.get(f"{API}/payments", params={"bot": "scout"}).json()["card"]["code_mismatch"] is mismatch


def test_old_card_when_the_master_was_replaced(client: TestClient, master: Path, vaults: Vaults) -> None:
    add_shop(client)
    vaults.records[master][0]["secret"]["card_number"] = "4000056655665556"
    [shop] = client.get(f"{API}/payments", params={"bot": "scout"}).json()["shops"]
    assert shop["stale"] is True


def test_add_shop_copies_the_master(client: TestClient, master: Path, vaults: Vaults, hermes_root: Path) -> None:
    vaults.next_ids.append("vault_8c1d2e3f4a5b")
    vaults.now = 1760610100.0
    response = add_shop(client, "WWW.Zalandö.se/kassa")
    assert response.status_code == 201
    assert response.json() == fixture("shop-created.json")
    [copy] = vaults.records[scout_vault(hermes_root)]
    assert copy["label"] == "Shopping card •••• 4242 · www.xn--zaland-1xa.se"
    assert copy["origin"] == "https://www.xn--zaland-1xa.se" and copy["kind"] == "payment"
    assert copy["secret"] == vaults.records[master][0]["secret"]
    assert "4242 4242" not in response.text


@pytest.mark.parametrize(("site", "host"), [
    ("https://www.zalando.se/checkout?step=2#pay", "www.zalando.se"),
    ("www.zalando.se", "www.zalando.se"),
    ("WWW.ZALANDO.SE", "www.zalando.se"),
    ("https://www.zalando.se:443/", "www.zalando.se"),
    ("  www.zalando.se.  ", "www.zalando.se"),
    ("https://user@shop.example.com", "shop.example.com"),
    ("bücher.de", "xn--bcher-kva.de"),
    ("https://xn--bcher-kva.de", "xn--bcher-kva.de"),
])
def test_site_normalisation(site: str, host: str) -> None:
    assert payments.shop_host(site) == host


@pytest.mark.parametrize(("site", "reason"), [
    ("http://www.zalando.se", "not_https"),
    ("ftp://www.zalando.se", "not_https"),
    ("https://192.168.1.10/checkout", "ip_address"),
    ("10.0.0.1", "ip_address"),
    ("https://[::1]/", "ip_address"),
    ("https://127.1", "ip_address"),
    ("localhost", "localhost"),
    ("https://shop.localhost", "localhost"),
    ("intranet", "localhost"),
    ("", "no_host"),
    ("https://", "no_host"),
    ("https://bad_host.example.com", "no_host"),
    ("https://-shop.example.com", "no_host"),
    ("https://www.zalando.se:8443", "port"),
    ("www.zalando.se:99999", "port"),
    ("https://[abc", "no_host"),
])
def test_invalid_sites(client: TestClient, master: Path, site: str, reason: str) -> None:
    with pytest.raises(payments.InvalidSite) as invalid:
        payments.shop_host(site)
    assert str(invalid.value) == reason
    response = add_shop(client, site)
    assert response.status_code == 400
    assert response.json() == fixture(f"error-invalid-site-{reason.replace('_', '-')}.json")


def test_duplicate_shop(client: TestClient, master: Path) -> None:
    add_shop(client)
    response = add_shop(client, "www.zalando.se")
    assert response.status_code == 409 and response.json() == fixture("error-duplicate-shop.json")


def test_add_shop_needs_exactly_one_master(client: TestClient, vaults: Vaults, hermes_root: Path) -> None:
    response = add_shop(client)
    assert response.status_code == 409 and response.json() == fixture("error-no-card.json")
    vaults.add(hermes_root / "vault", "payment", "Shop copy", CARD, "https://www.zalando.se")
    assert add_shop(client).json() == fixture("error-no-card.json")
    vaults.add(hermes_root / "vault" / "crew-push", "payment", "One", CARD)
    vaults.add(hermes_root / "vault" / "crew-push", "payment", "Two", CARD)
    response = add_shop(client)
    assert response.status_code == 409 and response.json() == fixture("error-several-cards.json")
    assert scout_vault(hermes_root) not in vaults.records or vaults.records[scout_vault(hermes_root)] == []


@pytest.mark.parametrize(("profile", "status", "name"), [
    ("Scout", 400, "error-invalid-profile.json"),
    ("../default", 400, "error-invalid-profile.json"),
    ("ghost", 404, "error-unknown-profile.json"),
])
def test_profile_errors(client: TestClient, vaults: Vaults, profile: str, status: int, name: str) -> None:
    for response in (client.get(f"{API}/payments", params={"bot": profile}),
                     add_shop(client, profile=profile),
                     client.delete(f"{API}/payments/shops/vault_3f9a1c2b7d4e", params={"bot": profile})):
        assert response.status_code == status and response.json() == fixture(name)


def test_bot_query_never_named_profile(client: TestClient, vaults: Vaults) -> None:
    for response in (client.get(f"{API}/payments", params={"profile": "scout"}),
                     client.delete(f"{API}/payments/shops/vault_3f9a1c2b7d4e", params={"profile": "scout"})):
        assert response.status_code == 422 and response.json()["detail"][0]["loc"] == ["query", "bot"]


def test_remove_shop(client: TestClient, master: Path, vaults: Vaults, hermes_root: Path) -> None:
    shop_id = add_shop(client).json()["shop"]["id"]
    response = client.delete(f"{API}/payments/shops/{shop_id}", params={"bot": "scout"})
    assert response.status_code == 200 and response.json() == fixture("shop-removed.json")
    response = client.delete(f"{API}/payments/shops/{shop_id}", params={"bot": "scout"})
    assert response.status_code == 404 and response.json() == fixture("error-unknown-shop.json")


def test_remove_refuses_the_master_and_other_kinds(client: TestClient, master: Path, vaults: Vaults,
                                                   hermes_root: Path) -> None:
    master_id = vaults.records[master][0]["id"]
    login = vaults.add(scout_vault(hermes_root), "login", "Zalando", {"password": "x"}, "https://www.zalando.se")
    for profile, item_id in (("default", master_id), ("scout", login.id), ("scout", master_id)):
        response = client.delete(f"{API}/payments/shops/{item_id}", params={"bot": profile})
        assert response.status_code == 404 and response.json() == fixture("error-unknown-shop.json")
    assert len(vaults.records[master]) == 1 and len(vaults.records[scout_vault(hermes_root)]) == 1


def test_request_lookup(client: TestClient) -> None:
    pending = {key: value for key, value in fixture("request-pending.json").items() if key != "now"}
    store.mutate_payments(lambda entries: [{**pending, "session_key": "agent:main:crew", "tool_call_id": "call_1",
                                            "command": "Fill payment card 'x' on https://www.zalando.se"}])
    response = client.get(f"{API}/payments/requests/{R}")
    assert response.status_code == 200
    body = response.json()
    assert abs(body["now"] - time.time()) < 60
    assert {**body, "now": 1760609941.2} == fixture("request-pending.json")
    response = client.get(f"{API}/payments/requests/{'0' * 32}")
    assert response.status_code == 404 and response.json() == fixture("error-unknown-request.json")


def test_log_keeps_the_newest_200() -> None:
    store.mutate_payments(lambda entries: [{"request_id": str(index)} for index in range(250)])
    entries = store.read_list("payments.json")
    assert len(entries) == 200 and entries[-1]["request_id"] == "249" and entries[0]["request_id"] == "50"


def test_a_dashboard_start_forgets_the_gate(plugin_api: types.ModuleType) -> None:
    store.write_gate(True)
    spec = importlib.util.spec_from_file_location("fresh_plugin_api", PLUGIN_ROOT / "dashboard" / "plugin_api.py")
    assert spec and spec.loader
    spec.loader.exec_module(importlib.util.module_from_spec(spec))
    assert store.read_gate() is None
