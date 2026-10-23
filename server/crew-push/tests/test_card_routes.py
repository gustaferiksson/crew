import fcntl
import json
import logging
import re
import threading
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from conftest import CARD, Vaults, fixture
from crew_push import payments, store
from test_payment_routes import API, add_shop, app, client, master, scout_vault  # noqa: F401

NUMBER = "4242424242424242"
NEW = {"card_number": "4000 0566 5566 5556", "exp_month": "3", "exp_year": "31", "cvc": "321",
       "cardholder_name": "Test Card", "label": "Travel card"}
SECRETS = ("4000056655665556", "4000 0566 5566 5556", "Test Card", NUMBER, "4242 4242 4242 4242")
CVC_LEAK = re.compile(r"(?<![\w.])321(?!\w|\.\d)")
NOW = datetime(2026, 10, 17, tzinfo=UTC)


def put_card(client: TestClient, **fields: str) -> Any:
    return client.put(f"{API}/payments/card", json={**NEW, **fields})


def masters(vaults: Vaults, hermes_root: Path) -> list[dict[str, Any]]:
    return [r for r in vaults.records.get(hermes_root / "vault" / "crew-push", []) if r["kind"] == "payment" and not r["origin"]]


def test_add_card_stores_the_normalised_card_without_origin(client: TestClient, vaults: Vaults,
                                                            hermes_root: Path) -> None:
    response = put_card(client)
    assert response.status_code == 200
    assert response.json() == {"card": {"label": "Travel card", "last4": "5556", "problem": None, "code_mismatch": False}}
    [card] = masters(vaults, hermes_root)
    assert card["label"] == "Travel card" and card["origin"] is None
    assert card["secret"] == {"card_number": "4000056655665556", "exp_month": "03", "exp_year": "2031", "cvc": "321",
                              "cardholder_name": "Test Card"}
    assert client.get(f"{API}/payments", params={"profile": "scout"}).json()["card"] == response.json()["card"]


def test_card_set_fixture(client: TestClient, vaults: Vaults) -> None:
    response = put_card(client, card_number="4242 4242 4242 4242", exp_month="12", exp_year="30", cvc="123",
                        label="Shopping card")
    assert response.json() == fixture("card-set.json")


def test_an_empty_name_is_left_out(client: TestClient, vaults: Vaults, hermes_root: Path) -> None:
    assert put_card(client, cardholder_name="  ").status_code == 200
    assert "cardholder_name" not in masters(vaults, hermes_root)[0]["secret"]


def test_replace_adds_the_new_card_then_removes_the_old(client: TestClient, master: Path, vaults: Vaults,
                                                         hermes_root: Path) -> None:
    add_shop(client)
    order: list[str] = []
    vault_type = type(payments.master_vault())
    real_add, real_remove = vault_type.add_item, vault_type.remove_item
    vault_type.add_item = lambda self, **kw: (order.append("add"), real_add(self, **kw))[1]
    vault_type.remove_item = lambda self, item_id: (order.append("remove"), real_remove(self, item_id))[1]
    response = put_card(client)
    assert response.status_code == 200 and order == ["add", "remove"]
    [card] = masters(vaults, hermes_root)
    assert card["secret"]["card_number"] == "4000056655665556"
    [shop] = client.get(f"{API}/payments", params={"profile": "scout"}).json()["shops"]
    assert shop["stale"] is True


def test_a_failed_remove_rolls_the_new_card_back(client: TestClient, master: Path, vaults: Vaults,
                                                 hermes_root: Path) -> None:
    vault_type = type(payments.master_vault())
    real_remove = vault_type.remove_item
    old_id = masters(vaults, hermes_root)[0]["id"]

    def remove(self: Any, item_id: str) -> bool:
        if item_id == old_id:
            raise OSError("disk full")
        return real_remove(self, item_id)

    vault_type.remove_item = remove
    response = put_card(client)
    assert response.status_code == 500 and response.json() == fixture("error-vault-error.json")
    assert [r["id"] for r in masters(vaults, hermes_root)] == [old_id]


def test_several_cards_writes_nothing(client: TestClient, master: Path, vaults: Vaults, hermes_root: Path) -> None:
    vaults.add(master, "payment", "Old card", CARD)
    response = put_card(client)
    assert response.status_code == 409 and response.json() == fixture("error-several-cards.json")
    assert len(masters(vaults, hermes_root)) == 2


def test_gate_off_refuses_and_writes_nothing(client: TestClient, app: FastAPI, vaults: Vaults,  # noqa: F811
                                             hermes_root: Path) -> None:
    for state in (False, None, "yes"):
        app.state.auth_required = state
        response = put_card(client)
        assert response.status_code == 403 and response.json() == fixture("error-login-off.json")
        response = client.post(f"{API}/payments/shops/update", json={"profile": "scout"})
        assert response.status_code == 403 and response.json() == fixture("error-login-off.json")
    assert masters(vaults, hermes_root) == []


def test_two_replaces_at_once_leave_one_card(master: Path, vaults: Vaults, hermes_root: Path) -> None:
    vault_type = type(payments.master_vault())
    real_add = vault_type.add_item

    def slow_add(self: Any, **kw: Any) -> Any:
        time.sleep(0.05)
        return real_add(self, **kw)

    vault_type.add_item = slow_add
    secrets = [payments.card_entry({**NEW, "label": f"Card {i}"}, NOW) for i in range(2)]
    threads = [threading.Thread(target=payments.set_master, args=secret) for secret in secrets]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    assert len(masters(vaults, hermes_root)) == 1


def test_every_vault_write_holds_the_lock(client: TestClient, master: Path, vaults: Vaults,
                                          hermes_root: Path) -> None:
    held: list[bool] = []
    vault_type = type(payments.master_vault())
    real_add, real_remove = vault_type.add_item, vault_type.remove_item

    def locked() -> bool:
        with open(store.data_dir() / ".vault.lock", "w") as probe:
            try:
                fcntl.flock(probe, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return True
            fcntl.flock(probe, fcntl.LOCK_UN)
            return False

    vault_type.add_item = lambda self, **kw: (held.append(locked()), real_add(self, **kw))[1]
    vault_type.remove_item = lambda self, item_id: (held.append(locked()), real_remove(self, item_id))[1]
    shop_id = add_shop(client).json()["shop"]["id"]
    assert put_card(client).status_code == 200
    assert client.post(f"{API}/payments/shops/update", json={"profile": "scout"}).status_code == 200
    add_shop(client, "www.apotea.se")
    client.delete(f"{API}/payments/shops/{shop_id}", params={"profile": "scout"})
    assert len(held) >= 6 and all(held)


@pytest.mark.parametrize(("fields", "reason"), [
    ({"card_number": "4242 4242 4242 4241"}, "number"),
    ({"card_number": "4242-4242-4242-424x"}, "number"),
    ({"card_number": "42424242"}, "number"),
    ({"card_number": "4242424242424242\n"}, "number"),
    ({"exp_month": "1\n2", "exp_year": "30"}, "expiry"),
    ({"card_number": ""}, "number"),
    ({"exp_month": "13"}, "expiry"),
    ({"exp_month": "00"}, "expiry"),
    ({"exp_year": "203"}, "expiry"),
    ({"exp_year": "2050"}, "expiry"),
    ({"exp_month": "8", "exp_year": "2026"}, "expired"),
    ({"exp_month": "1", "exp_year": "25"}, "expired"),
    ({"cvc": "12"}, "cvc"),
    ({"cvc": "1234"}, "cvc"),
    ({"card_number": "3782 822463 10005", "cvc": "123"}, "cvc"),
    ({"cardholder_name": "x" * 65}, "name"),
    ({"label": ""}, "label"),
    ({"label": "x" * 41}, "label"),
    ({"label": "Visa •••• 9999"}, "label"),
    ({"label": "Bob's card"}, "label"),
    ({"label": "Card · shop"}, "label"),
    ({"label": "Two\nlines"}, "label"),
    ({"label": "Zero​width"}, "label"),
    ({"cvc": 123}, "body"),
])
def test_invalid_cards(client: TestClient, vaults: Vaults, hermes_root: Path, fields: dict[str, Any],
                       reason: str) -> None:
    with pytest.raises(payments.InvalidCard) as invalid:
        payments.card_entry({**NEW, **fields}, NOW)
    assert str(invalid.value) == reason
    response = put_card(client, **fields)
    assert response.status_code == 400
    assert response.json() == fixture(f"error-invalid-card-{reason}.json")
    assert masters(vaults, hermes_root) == []


@pytest.mark.parametrize("fields", [
    {"exp_month": "9", "exp_year": "2026"},
    {"exp_month": "10", "exp_year": "26"},
    {"exp_month": "12", "exp_year": "2046"},
    {"card_number": "3782 822463 10005", "cvc": "1234"},
    {"card_number": "6011111111111117"},
    {"label": "Résa 2026"},
])
def test_valid_cards(fields: dict[str, str]) -> None:
    label, secret = payments.card_entry({**NEW, **fields}, NOW)
    assert label and secret["exp_month"].isdigit() and len(secret["exp_year"]) == 4


@pytest.mark.parametrize("body", [b"[]", b'"4242424242424242"', b"not json", b"\xff\xfe"])
def test_bodies_that_are_not_an_object(client: TestClient, vaults: Vaults, body: bytes) -> None:
    response = client.put(f"{API}/payments/card", content=body, headers={"Content-Type": "application/json"})
    assert response.status_code == 400 and response.json() == fixture("error-invalid-card-body.json")
    assert "4242" not in response.text


def test_a_form_post_is_refused(client: TestClient, vaults: Vaults, hermes_root: Path) -> None:
    for headers in ({"Content-Type": "text/plain"}, {"Content-Type": "application/x-www-form-urlencoded"}, {}):
        response = client.put(f"{API}/payments/card", content=b'{"card_number": "4242424242424242"}', headers=headers)
        assert response.status_code == 400 and response.json() == fixture("error-invalid-card-body.json")
    assert masters(vaults, hermes_root) == []


def test_the_card_never_reaches_logs_responses_or_files(client: TestClient, app: FastAPI,  # noqa: F811
                                                         master: Path, vaults: Vaults, hermes_root: Path,
                                                         caplog: pytest.LogCaptureFixture,
                                                         capfd: pytest.CaptureFixture[str],
                                                         monkeypatch: pytest.MonkeyPatch) -> None:
    caplog.set_level(logging.DEBUG)
    texts = [put_card(client).text]
    texts += [put_card(client, **fields).text for fields in (
        {"card_number": "4000 0566 5566 5557"}, {"exp_month": "13"}, {"cvc": "12"}, {"label": ""},
        {"cardholder_name": "Test Card" * 9}, {"exp_year": "2020"})]
    texts.append(client.put(f"{API}/payments/card", content=b'["4000056655665556", "321"]',
                            headers={"Content-Type": "application/json"}).text)
    texts.append(client.post(f"{API}/payments/shops/update", json={"profile": "scout"}).text)
    texts.append(client.get(f"{API}/payments", params={"profile": "scout"}).text)
    vault_type = type(payments.master_vault())

    def leaky(self: Any, **kw: Any) -> Any:
        raise RuntimeError(f"cannot store {kw['secret']}")

    monkeypatch.setattr(vault_type, "add_item", leaky)
    texts.append(put_card(client).text)
    monkeypatch.setattr(payments, "card_entry", lambda body, now: (_ for _ in ()).throw(ValueError(str(body))))
    texts.append(put_card(client).text)
    app.state.auth_required = False
    texts.append(put_card(client).text)
    captured = capfd.readouterr()
    files = "".join(path.read_text(errors="replace") for path in (hermes_root / "plugin-data").rglob("*")
                    if path.is_file())
    for where, text in (("logs", caplog.text), ("stdout", captured.out), ("stderr", captured.err),
                        ("responses", "".join(texts)), ("plugin-data", files)):
        assert not CVC_LEAK.search(text), f"'321' leaked into {where}"
        for secret in SECRETS:
            assert secret not in text, f"{secret!r} leaked into {where}"
    assert texts[-3:-1] == [fixture_text("error-vault-error.json")] * 2


def fixture_text(name: str) -> str:
    return json.dumps(fixture(name), separators=(",", ":"))


def test_update_shops_recopies_only_stale_shops(client: TestClient, master: Path, vaults: Vaults,
                                                hermes_root: Path) -> None:
    vaults.next_ids.extend(["vault_3f9a1c2b7d4e", "vault_8c1d2e3f4a5b", "vault_1a2b3c4d5e6f"])
    add_shop(client)
    put_card(client, card_number="4242 4242 4242 4242", exp_month="12", exp_year="30", cvc="123",
             cardholder_name="Gustaf Eriksson", label="Shopping card")
    fresh = add_shop(client, "www.apotea.se").json()["shop"]
    vaults.add(scout_vault(hermes_root), "payment", "Hand added", {**CARD, "card_number": "5555555555554444"},
               "https://www.apotea.se")
    (hermes_root / "profiles" / "ada").mkdir()
    vaults.add(hermes_root / "profiles" / "ada" / "vault", "payment", "Ada copy", CARD, "https://www.zalando.se")
    vaults.next_ids.append("vault_5e6f7a8b9c0d")
    vaults.now = 1760620000.0
    stale_before = [s for s in client.get(f"{API}/payments", params={"profile": "scout"}).json()["shops"] if s["stale"]]
    assert len(stale_before) == 2

    response = client.post(f"{API}/payments/shops/update", json={"profile": "scout"})
    assert response.status_code == 200
    shops = response.json()["shops"]
    assert [(s["host"], s["stale"]) for s in shops] == [("www.apotea.se", False), ("www.zalando.se", False)]
    assert shops[0]["id"] == fresh["id"]
    records = vaults.records[scout_vault(hermes_root)]
    assert [r["label"] for r in records] == ["Shopping card •••• 4242 · www.apotea.se",
                                             "Shopping card •••• 4242 · www.zalando.se"]
    assert all(r["secret"] == masters(vaults, hermes_root)[0]["secret"] for r in records)
    assert vaults.records[hermes_root / "profiles" / "ada" / "vault"][0]["label"] == "Ada copy"
    assert response.json() == fixture("shops-updated.json")


def test_update_shops_finishes_a_half_done_run(client: TestClient, master: Path, vaults: Vaults,
                                               hermes_root: Path) -> None:
    add_shop(client)
    vaults.add(scout_vault(hermes_root), "payment", "Old copy", {**CARD, "card_number": "5555555555554444"},
               "https://www.zalando.se")
    response = client.post(f"{API}/payments/shops/update", json={"profile": "scout"})
    assert [s["stale"] for s in response.json()["shops"]] == [False]
    assert len(vaults.records[scout_vault(hermes_root)]) == 1


def test_update_shops_waits_for_a_pending_payment(client: TestClient, master: Path, vaults: Vaults) -> None:
    add_shop(client)
    store.mutate_payments(lambda entries: [{"request_id": "a" * 32, "profile": "scout", "state": "pending",
                                            "expires_at": time.time() + 200}])
    response = client.post(f"{API}/payments/shops/update", json={"profile": "scout"})
    assert response.status_code == 409 and response.json() == fixture("error-payment-pending.json")
    store.mutate_payments(lambda entries: [{**entries[0], "expires_at": time.time() - 1}])
    assert client.post(f"{API}/payments/shops/update", json={"profile": "scout"}).status_code == 200


def test_update_shops_errors(client: TestClient, vaults: Vaults, hermes_root: Path) -> None:
    response = client.post(f"{API}/payments/shops/update", json={"profile": "scout"})
    assert response.status_code == 409 and response.json() == fixture("error-no-card.json")
    vaults.add(hermes_root / "vault" / "crew-push", "payment", "One", CARD)
    vaults.add(hermes_root / "vault" / "crew-push", "payment", "Two", CARD)
    response = client.post(f"{API}/payments/shops/update", json={"profile": "scout"})
    assert response.status_code == 409 and response.json() == fixture("error-several-cards.json")
    for profile, status, name in (("Scout", 400, "error-invalid-profile.json"),
                                  ("ghost", 404, "error-unknown-profile.json")):
        response = client.post(f"{API}/payments/shops/update", json={"profile": profile})
        assert response.status_code == status and response.json() == fixture(name)


def test_a_new_label_makes_shops_stale(client: TestClient, master: Path, vaults: Vaults, hermes_root: Path) -> None:
    put_card(client, card_number="4242 4242 4242 4242", exp_month="12", exp_year="30", cvc="123",
             cardholder_name="Gustaf Eriksson", label="Shopping card")
    add_shop(client)
    assert not client.get(f"{API}/payments", params={"profile": "scout"}).json()["shops"][0]["stale"]
    put_card(client, card_number="4242 4242 4242 4242", exp_month="12", exp_year="30", cvc="123",
             cardholder_name="Gustaf Eriksson", label="Travel card")
    assert client.get(f"{API}/payments", params={"profile": "scout"}).json()["shops"][0]["stale"]
    client.post(f"{API}/payments/shops/update", json={"profile": "scout"})
    [copy] = vaults.records[scout_vault(hermes_root)]
    assert copy["label"] == "Travel card •••• 4242 · www.zalando.se"
