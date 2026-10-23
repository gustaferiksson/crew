from pathlib import Path
from typing import Any

from fastapi.testclient import TestClient

from conftest import CARD, Vaults
from test_payment_routes import API, add_shop, app, client, scout_vault  # noqa: F401

OTHER = {**CARD, "card_number": "4000056655665556"}


def origin_less(vaults: Vaults, base: Path) -> list[dict[str, Any]]:
    return [r for r in vaults.records.get(base, []) if r["kind"] == "payment" and not r["origin"]]


def payments(client: TestClient) -> dict[str, Any]:
    return client.get(f"{API}/payments", params={"profile": "scout"}).json()


def test_the_legacy_master_moves_into_crew_push_vault(client: TestClient, vaults: Vaults, hermes_root: Path) -> None:
    vaults.add(hermes_root / "vault", "payment", "Shopping card", CARD)
    vaults.add(hermes_root / "vault", "login", "example.com", {"password": "x"}, "https://example.com")
    body = payments(client)
    assert body["card"] == {"label": "Shopping card", "last4": "4242", "problem": None, "code_mismatch": False} and body["legacy_cards"] == 0
    [card] = origin_less(vaults, hermes_root / "vault" / "crew-push")
    assert card["label"] == "Shopping card" and card["secret"] == CARD
    assert origin_less(vaults, hermes_root / "vault") == []
    assert [r["kind"] for r in vaults.records[hermes_root / "vault"]] == ["login"]


def test_the_move_is_idempotent(client: TestClient, vaults: Vaults, hermes_root: Path) -> None:
    vaults.add(hermes_root / "vault", "payment", "Shopping card", CARD)
    first, second = payments(client), payments(client)
    assert first == second
    assert len(origin_less(vaults, hermes_root / "vault" / "crew-push")) == 1


def test_a_half_done_move_is_finished(client: TestClient, vaults: Vaults, hermes_root: Path) -> None:
    vaults.add(hermes_root / "vault" / "crew-push", "payment", "Shopping card", CARD)
    vaults.add(hermes_root / "vault", "payment", "Shopping card", CARD)
    assert payments(client)["legacy_cards"] == 0
    assert origin_less(vaults, hermes_root / "vault") == []
    assert len(origin_less(vaults, hermes_root / "vault" / "crew-push")) == 1


def test_a_different_legacy_card_is_left_alone(client: TestClient, vaults: Vaults, hermes_root: Path) -> None:
    vaults.add(hermes_root / "vault" / "crew-push", "payment", "Travel card", OTHER)
    vaults.add(hermes_root / "vault", "payment", "Shopping card", CARD)
    body = payments(client)
    assert body["legacy_cards"] == 1 and body["card"]["label"] == "Travel card"
    assert len(origin_less(vaults, hermes_root / "vault")) == 1


def test_several_legacy_cards_are_left_alone(client: TestClient, vaults: Vaults, hermes_root: Path) -> None:
    vaults.add(hermes_root / "vault", "payment", "One", CARD)
    vaults.add(hermes_root / "vault", "payment", "Two", OTHER)
    body = payments(client)
    assert body["legacy_cards"] == 2 and body["card"]["problem"] == "missing"
    assert origin_less(vaults, hermes_root / "vault" / "crew-push") == []


def test_shop_copies_stay_in_the_bot_vault(client: TestClient, vaults: Vaults, hermes_root: Path) -> None:
    vaults.add(hermes_root / "vault", "payment", "Shopping card", CARD)
    assert add_shop(client).status_code == 201
    [shop] = vaults.records[scout_vault(hermes_root)]
    assert shop["origin"] == "https://www.zalando.se" and shop["secret"] == CARD
    assert payments(client)["shops"][0]["stale"] is False


def test_add_shop_migrates_first(client: TestClient, vaults: Vaults, hermes_root: Path) -> None:
    vaults.add(hermes_root / "vault", "payment", "Shopping card", CARD)
    assert add_shop(client).status_code == 201
    assert origin_less(vaults, hermes_root / "vault") == []


def test_status_lists_the_card_vault(client: TestClient) -> None:
    assert "card_vault" in client.get(f"{API}/status").json()["features"]
