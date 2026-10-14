from typing import Any, Callable

from crew_push.fanout import serve_every_profile
from crew_push.hooks import CrewPush


class Dispatch:
    def invoke_hook(self, hook_name: str, **kwargs: Any) -> list[Any]:
        return [callback(**kwargs) for callback in self.callbacks.get(hook_name, [])]

    def has_hook(self, hook_name: str) -> bool:
        return bool(self.callbacks.get(hook_name))

    def iter_hook_callbacks(self, hook_name: str) -> tuple[Callable[..., Any], ...]:
        return tuple(self.callbacks.get(hook_name, []))


class Manager(Dispatch):
    def __init__(self) -> None:
        self.callbacks: dict[str, list[Callable[..., Any]]] = {}


def turn(manager: Manager) -> None:
    manager.invoke_hook("pre_llm_call", session_id="s1", platform="tui")
    manager.invoke_hook("post_llm_call", session_id="s1", assistant_response="Done.")
    manager.invoke_hook("on_session_end", session_id="s1", turn_id="t1", completed=True)


def test_profile_without_own_copy_is_served(device, enqueued: list) -> None:
    device()
    profile = ["beta"]
    undo = serve_every_profile(Manager, lambda: profile[0])
    assert undo is not None
    try:
        manager = Manager()
        assert manager.has_hook("on_session_end")
        assert manager.has_hook("post_tool_call") is False
        turn(manager)
        [(_, _, payload)] = enqueued
        assert payload["crew"]["profile"] == "beta"
        assert serve_every_profile(Manager, lambda: "other") is None
    finally:
        undo()
    assert "invoke_hook" not in Manager.__dict__ and "has_hook" not in Manager.__dict__
    assert Manager().has_hook("on_session_end") is False


def test_profile_with_own_copy_is_not_doubled(device, enqueued: list) -> None:
    device()
    undo = serve_every_profile(Manager, lambda: "atlas")
    assert undo is not None
    try:
        manager = Manager()
        own = CrewPush(profile="atlas")
        for name in ("pre_llm_call", "post_llm_call", "on_session_end"):
            manager.callbacks[name] = [getattr(own, name)]
        turn(manager)
        assert len(enqueued) == 1
    finally:
        undo()


def test_host_without_dispatch_methods_is_left_alone() -> None:
    class Bare:
        pass
    assert serve_every_profile(Bare, lambda: "default") is None
    assert not hasattr(Bare, "invoke_hook")
