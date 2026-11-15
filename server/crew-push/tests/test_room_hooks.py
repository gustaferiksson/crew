import json
import re
import sys
import types
from pathlib import Path
from typing import Any

import pytest

from conftest import PLUGIN_ROOT
from crew_push.hooks import CrewPush

ROOMS = PLUGIN_ROOT.parents[1] / "Tests" / "fixtures" / "rooms"
LISTED = json.loads((ROOMS / "list.json").read_text())["rooms"]
ROOM = next(room for room in LISTED if room["name"] == "Crew list two")
RECORDED = next(row for row in json.loads((ROOMS / "session.list.after.json").read_text())["sessions"]
                if row["title"].startswith("Group: "))
SESSION = "20261114_101500_c0ffee"


@pytest.fixture(autouse=True)
def rooms(monkeypatch: pytest.MonkeyPatch, session_rows: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    listed = [dict(room) for room in LISTED]
    session_rows[SESSION] = {**RECORDED, "id": SESSION, "title": f"Group: {ROOM['room_id']}"}
    session_rows[RECORDED["id"]] = RECORDED
    session_rows["20261114_090000_aaaaaa"] = {"id": "20261114_090000_aaaaaa", "source": "tui", "title": f"Group: {ROOM['room_id']}"}
    monkeypatch.setitem(sys.modules, "gateway", types.ModuleType("gateway"))
    monkeypatch.setitem(sys.modules, "gateway.hosted_rooms", types.SimpleNamespace(
        default_db_path=lambda: Path("shared-state.db"), list_rooms=lambda db_path: listed))
    monkeypatch.setitem(sys.modules, "gateway.hosted_room_discussion", types.SimpleNamespace(
        is_pass_text=lambda value: not str(value or "").strip()
        or re.fullmatch(r"\(?\s*pass\s*\)?\.?", str(value).strip(), re.IGNORECASE) is not None))
    return listed


@pytest.fixture
def push(device) -> CrewPush:
    device()
    return CrewPush(profile="crew-test")


def turn(push: CrewPush, reply: str, session_id: str = SESSION, turn_id: str = "t1", **end: Any) -> None:
    push.pre_llm_call(session_id=session_id, platform="bot_room", user_message="status?")
    push.post_llm_call(session_id=session_id, assistant_response=reply)
    push.on_session_end(**{"session_id": session_id, "turn_id": turn_id, "completed": True, "failed": False,
                           "interrupted": False, "platform": "bot_room", **end})


def test_member_reply_pushes_into_the_room_thread(push: CrewPush, enqueued: list, hermes_root: Path) -> None:
    (hermes_root / "plugin-data" / "crew-push" / "install_id").write_text("9f2c41d07ab35e11")
    turn(push, "**Build is green.** Deploying `v2`.")
    [(_, headers, payload)] = enqueued
    assert payload == json.loads((ROOMS / "push-room-reply.json").read_text())
    assert payload["aps"]["alert"] == {"title": "Crew list two", "subtitle": "Crew Test",
                                       "body": "Build is green. Deploying v2."}
    assert payload["aps"]["thread-id"] == f"group:{ROOM['room_id']}"
    assert payload["aps"]["category"] == "CREW_REPLY"
    assert payload["crew"]["room_id"] == ROOM["room_id"] and payload["crew"]["profile"] == "crew-test"
    assert payload["crew"]["kind"] == "reply" and payload["crew"]["session_id"] == SESSION
    assert headers["apns-collapse-id"].startswith("reply.")


def test_each_member_message_stays_in_the_stack(push: CrewPush, enqueued: list) -> None:
    turn(push, "First.", turn_id="t1")
    turn(push, "Second.", turn_id="t2")
    assert len({headers["apns-collapse-id"] for _, headers, _ in enqueued}) == 2


def test_card_reply_shows_its_title(push: CrewPush, enqueued: list) -> None:
    card = {"updateComponents": {"components": [{"id": "h", "component": "Header", "title": "Deploy plan"}]}}
    turn(push, f"```a2ui\n{json.dumps(card)}\n```")
    assert enqueued[0][2]["aps"]["alert"]["body"] == "Deploy plan"


@pytest.mark.parametrize("reply", ["pass", "(pass)", "Pass."])
def test_pass_is_silent(push: CrewPush, enqueued: list, reply: str) -> None:
    turn(push, reply)
    assert enqueued == []


def test_failed_and_interrupted_member_turns_are_silent(push: CrewPush, enqueued: list) -> None:
    turn(push, "", completed=False, failed=True, turn_exit_reason="Provider timed out")
    turn(push, "half an answer", turn_id="t2", completed=False, interrupted=True)
    assert enqueued == []


def test_compressed_room_session_pushes(push: CrewPush, enqueued: list,
                                       session_rows: dict[str, dict[str, Any]]) -> None:
    session_rows["20261114_120000_d00d00"] = {**RECORDED, "id": "20261114_120000_d00d00", "root": SESSION,
                                              "title": f"Group: {ROOM['room_id']} #2"}
    turn(push, "After compression.", session_id="20261114_120000_d00d00")
    assert enqueued[0][2]["crew"]["room_id"] == ROOM["room_id"]


def test_disbanded_room_is_silent(push: CrewPush, enqueued: list) -> None:
    turn(push, "Done.", session_id=RECORDED["id"])
    assert enqueued == []


def test_group_title_outside_a_room_session_is_silent(push: CrewPush, enqueued: list) -> None:
    turn(push, "Done.", session_id="20261114_090000_aaaaaa")
    assert enqueued == []


def test_renamed_room_uses_the_new_name(push: CrewPush, enqueued: list, rooms: list[dict[str, Any]]) -> None:
    turn(push, "One.", turn_id="t1")
    next(room for room in rooms if room["room_id"] == ROOM["room_id"])["name"] = "Launch"
    turn(push, "Two.", turn_id="t2")
    assert [p["aps"]["alert"]["title"] for _, _, p in enqueued] == ["Crew list two", "Launch"]


def test_room_approval(push: CrewPush, enqueued: list, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setitem(sys.modules, "agent", types.ModuleType("agent"))
    monkeypatch.setitem(sys.modules, "agent.redact", types.SimpleNamespace(redact_sensitive_text=lambda text, force: text))
    push.pre_llm_call(session_id=SESSION, platform="bot_room")
    push.pre_approval_request(command="rm -rf build", description="Delete the build folder?", session_id=SESSION,
                              session_key=SESSION, surface="gateway", tool_call_id="call-1")
    [(_, headers, payload)] = enqueued
    assert payload["aps"]["alert"] == {"title": "Crew list two", "subtitle": "Crew Test · Delete the build folder?",
                                       "body": "rm -rf build"}
    assert payload["aps"]["thread-id"] == f"group:{ROOM['room_id']}"
    assert payload["aps"]["interruption-level"] == "time-sensitive"
    assert payload["crew"]["kind"] == "approval" and payload["crew"]["room_id"] == ROOM["room_id"]


def test_previews_off_hide_member_and_text(device, enqueued: list) -> None:
    device(previews=False)
    turn(CrewPush(profile="crew-test"), "Secret plan.")
    assert enqueued[0][2]["aps"]["alert"] == {"title": "Crew list two", "body": "Replied"}


def test_replies_pref_off_is_silent(device, enqueued: list) -> None:
    device(replies=False)
    turn(CrewPush(profile="crew-test"), "Done.")
    assert enqueued == []
