import json
from pathlib import Path
from typing import Any

import pytest

from conftest import BOT_CHAT
from crew_push.hooks import CrewPush

SCENARIOS = Path(__file__).resolve().parents[3] / "Tests" / "fixtures" / "scenarios"


def replay(push: CrewPush, history: Path) -> None:
    turns: list[list[dict[str, Any]]] = []
    for row in json.loads(history.read_text()):
        if row["role"] == "user":
            turns.append([])
        if turns:
            turns[-1].append(row)
    for rows in turns:
        replies = [row["content"] for row in rows if row["role"] == "assistant" and row.get("content") and not row.get("tool_calls")]
        push.pre_llm_call(session_id=BOT_CHAT, platform="tui", user_message=rows[0]["content"])
        push.post_llm_call(session_id=BOT_CHAT, assistant_response=replies[-1] if replies else "")
        push.on_session_end(session_id=BOT_CHAT, turn_id=str(rows[0]["id"]), completed=True, platform="tui")


@pytest.mark.parametrize(("profile", "bodies"), [
    pytest.param("crew-test", ["👋", "@crew-test-peer replied: “Hello! Great to hear from you.”"],
                 id="sender-pushes-its-reply-and-the-relay-not-the-hidden-turn"),
    pytest.param("crew-test-peer", ["Crew Test received the greeting."],
                 id="mentioned-bot-still-pushes-the-delivery-turn-crew-hides"),
])
def test_bot_mention_pushes(device, enqueued: list, profile: str, bodies: list[str]) -> None:
    device()
    replay(CrewPush(profile=profile), SCENARIOS / "bot-mention" / f"{profile}.history.json")
    assert [payload["aps"]["alert"]["body"] for _, _, payload in enqueued] == bodies
