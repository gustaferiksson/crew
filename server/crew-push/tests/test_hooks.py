import sys
import types
from typing import Any

import pytest

from crew_push.hooks import CrewPush, plain

SESSION = "20261013_101512_ab12cd"


@pytest.fixture
def push(device) -> CrewPush:
    device()
    return CrewPush(profile="atlas")


@pytest.fixture
def hermes_helpers(monkeypatch: pytest.MonkeyPatch) -> None:
    modules = {
        "agent": types.ModuleType("agent"),
        "agent.redact": types.SimpleNamespace(redact_sensitive_text=lambda text, force: text.replace("hunter2", "***")),
        "tools": types.ModuleType("tools"),
        "tools.approval": types.SimpleNamespace(
            list_gateway_approvals=lambda key: [{"request_id": "old"}, {"request_id": "c0ffee"}] if key == SESSION else []),
        "cron": types.ModuleType("cron"),
        "cron.jobs": types.SimpleNamespace(get_job=lambda job_id: {"name": "Morning brief"} if job_id == "a1b2" else None),
        "hermes_cli": types.ModuleType("hermes_cli"),
        "hermes_cli.profiles": types.SimpleNamespace(
            get_profile_dir=lambda name: name,
            read_profile_meta=lambda directory: {"bot_title": "Atlas" if directory == "atlas" else ""}),
    }
    for name, module in modules.items():
        monkeypatch.setitem(sys.modules, name, module)


def turn(push: CrewPush, reply: str = "**Done.** See `out.txt`.", platform: str = "tui",
         session_id: str = SESSION, **end: Any) -> None:
    push.pre_llm_call(session_id=session_id, platform=platform, telemetry_schema_version=1)
    push.post_llm_call(session_id=session_id, assistant_response=reply, user_message="hi")
    push.on_session_end(**{"session_id": session_id, "turn_id": "t1", "completed": True, "failed": False,
                           "interrupted": False, "platform": platform, **end})


def test_reply(push: CrewPush, enqueued: list, hermes_helpers: None) -> None:
    turn(push)
    [(device, headers, payload)] = enqueued
    assert payload["aps"] == {
        "alert": {"title": "Atlas", "body": "Done. See out.txt."}, "sound": "default",
        "thread-id": "profile.atlas", "category": "CREW_REPLY", "interruption-level": "active",
    }
    crew = payload["crew"]
    assert crew["kind"] == "reply" and crew["profile"] == "atlas" and crew["session_id"] == SESSION
    assert crew["v"] == 1 and len(crew["install_id"]) == 16 and len(crew["event_id"]) == 16
    assert "request_id" not in crew
    assert headers["apns-priority"] == "10"
    assert headers["apns-collapse-id"].startswith("reply.")
    assert int(headers["apns-expiration"]) > 0


def test_turn_error(push: CrewPush, enqueued: list) -> None:
    turn(push, reply="", completed=False, failed=True, turn_exit_reason="Provider timed out")
    [(_, _, payload)] = enqueued
    assert payload["crew"]["kind"] == "turn_error"
    assert payload["aps"]["alert"] == {"title": "atlas", "body": "Provider timed out"}


def test_approval(push: CrewPush, enqueued: list, hermes_helpers: None) -> None:
    push.pre_llm_call(session_id=SESSION, platform="tui")
    push.pre_approval_request(command="PGPASSWORD=hunter2 psql -f 0042.sql", description="Run the migration?",
                              session_key=SESSION, session_id=SESSION, surface="gateway", tool_call_id="call-9")
    [(_, headers, payload)] = enqueued
    assert payload["aps"]["alert"] == {"title": "Atlas", "subtitle": "Run the migration?",
                                       "body": "PGPASSWORD=*** psql -f 0042.sql"}
    assert payload["aps"]["category"] == "CREW_APPROVAL"
    assert payload["aps"]["interruption-level"] == "time-sensitive"
    assert payload["crew"]["request_id"] == "c0ffee"
    assert int(headers["apns-expiration"]) - int(__import__("time").time()) <= 300


def test_approval_without_redaction_hides_the_command(push: CrewPush, enqueued: list,
                                                      monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setitem(sys.modules, "agent.redact", None)
    push.pre_llm_call(session_id=SESSION, platform="tui")
    push.pre_approval_request(command="secret", session_id=SESSION, session_key=SESSION, surface="gateway")
    assert enqueued[0][2]["aps"]["alert"]["body"] == "Needs your approval."


def test_question(push: CrewPush, enqueued: list) -> None:
    push.pre_llm_call(session_id=SESSION, platform="tui")
    push.pre_tool_call(tool_name="terminal", args={"command": "ls"}, session_id=SESSION, tool_call_id="c1")
    push.pre_tool_call(tool_name="clarify", args={"questions": [{"question": "Which *branch*?"}, {"question": "x"}]},
                       session_id=SESSION, tool_call_id="c2")
    push.pre_tool_call(tool_name="clarify", args={"question": "Legacy shape?"}, session_id=SESSION, tool_call_id="c3")
    assert [p["aps"]["alert"]["body"] for _, _, p in enqueued] == ["Which branch?", "Legacy shape?"]
    assert enqueued[0][2]["aps"]["category"] == "CREW_QUESTION"


def test_question_with_garbage_args_never_raises(push: CrewPush, enqueued: list) -> None:
    push.pre_llm_call(session_id=SESSION, platform="tui")
    push.pre_tool_call(tool_name="clarify", args={"questions": "nope"}, session_id=SESSION, tool_call_id="c")
    assert enqueued[0][2]["aps"]["alert"]["body"] == "Has a question for you."


def test_routine(device, enqueued: list, hermes_helpers: None) -> None:
    device("cd" * 32, routines=True)
    device()
    push = CrewPush(profile="atlas")
    turn(push, reply="Three new emails.", platform="cron", session_id="cron_a1b2_20261013_070000")
    [(target, headers, payload)] = enqueued
    assert target["token"] == "cd" * 32
    assert payload["aps"]["alert"] == {"title": "Atlas", "subtitle": "Morning brief", "body": "Three new emails."}
    assert payload["aps"]["interruption-level"] == "passive"
    assert headers["apns-priority"] == "5"


def test_previews_off_sends_generic_text(device, enqueued: list) -> None:
    device(previews=False)
    push = CrewPush(profile="atlas")
    turn(push)
    assert enqueued[0][2]["aps"]["alert"] == {"title": "atlas", "body": "Replied"}


def test_long_reply_is_clipped() -> None:
    from crew_push.hooks import clip
    assert len(clip("word " * 500, 400)) == 400


@pytest.mark.parametrize("change", [
    {"interrupted": True},
    {"platform": "telegram"},
    {"platform": ""},
    {"session_id": "kanban_task_1"},
    {"reply": "", "completed": True},
    {"completed": False},
])
def test_skipped_turns(push: CrewPush, enqueued: list, change: dict) -> None:
    turn(push, **change)
    assert enqueued == []


def test_subagent_turns_are_muted(push: CrewPush, enqueued: list) -> None:
    push.subagent_start(parent_session_id=SESSION, child_session_id="child-1")
    turn(push, session_id="child-1")
    assert enqueued == []


def test_smart_approvals_are_skipped(push: CrewPush, enqueued: list) -> None:
    push.pre_llm_call(session_id=SESSION, platform="tui")
    push.pre_approval_request(command="ls", session_id=SESSION, surface="smart")
    assert enqueued == []


def test_unknown_session_fails_closed(push: CrewPush, enqueued: list) -> None:
    push.pre_approval_request(command="ls", session_id="never-seen", surface="gateway")
    push.pre_tool_call(tool_name="clarify", args={"question": "?"}, session_id="never-seen")
    assert enqueued == []


def test_same_event_is_sent_once(push: CrewPush, enqueued: list) -> None:
    push.pre_llm_call(session_id=SESSION, platform="tui")
    for _ in range(2):
        push.pre_tool_call(tool_name="clarify", args={"question": "?"}, session_id=SESSION, tool_call_id="c1")
    assert len(enqueued) == 1


def test_prefs_filter_devices(device, enqueued: list) -> None:
    device(replies=False)
    turn(CrewPush(profile="atlas"))
    assert enqueued == []


def test_markdown_flattening() -> None:
    text = "# Title\n- item one\n> quote\n[link](https://x) ![img](a.png)\n```py\nprint(1)\n```\nsnake_case 2*3"
    assert " ".join(plain(text).split()) == "Title item one quote link img print(1) snake_case 2*3"
