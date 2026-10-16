import logging
import threading
from typing import Any, Callable

from . import payments
from .hooks import HOOK_NAMES, CrewPush

log = logging.getLogger("crew_push")

# Lives on the manager class: Hermes imports a fresh module copy per profile, and each must see it.
MARK = "_crew_push_serves_every_profile"
WRAPPED = ("invoke_hook", "has_hook")
_lock = threading.Lock()


def has_own_copy(manager: Any, hook_name: str) -> bool:
    return any(getattr(getattr(callback, "__self__", None), "is_crew_push", False)
               for callback in manager.iter_hook_callbacks(hook_name))


def serve_every_profile(manager_class: type, active_profile: Callable[[], str]) -> Callable[[], None] | None:
    with _lock:
        if getattr(manager_class, MARK, None) is not None:
            return None
        if not all(callable(getattr(manager_class, name, None)) for name in (*WRAPPED, "iter_hook_callbacks")):
            log.warning("crew-push: this Hermes cannot share one install across profiles; "
                        "enable the plugin in every profile that should push")
            return None
        own = {name: manager_class.__dict__.get(name) for name in WRAPPED}
        invoke, has = manager_class.invoke_hook, manager_class.has_hook
        pushes: dict[str, CrewPush] = {}

        def push_for_active_profile() -> CrewPush:
            profile = active_profile()
            with _lock:
                if profile not in pushes:
                    pushes[profile] = CrewPush(profile=profile)
                return pushes[profile]

        def invoke_hook(self: Any, hook_name: str, **kwargs: Any) -> list[Any]:
            results = invoke(self, hook_name, **kwargs)
            try:
                if hook_name in HOOK_NAMES and not has_own_copy(self, hook_name):
                    result = getattr(push_for_active_profile(), hook_name)(**kwargs)
                    if result is not None:
                        results.append(result)
            except Exception:
                log.warning("crew-push: serving %s for a profile without its own copy failed", hook_name,
                            exc_info=True)
                if hook_name == "pre_tool_call":
                    results.append(payments.block("crew_check_failed"))
            return results

        def has_hook(self: Any, hook_name: str) -> bool:
            return hook_name in HOOK_NAMES or has(self, hook_name)

        manager_class.invoke_hook, manager_class.has_hook = invoke_hook, has_hook
        token = object()
        setattr(manager_class, MARK, token)

    def undo() -> None:
        with _lock:
            if getattr(manager_class, MARK, None) is not token:
                return
            for name, original in own.items():
                if original is None:
                    delattr(manager_class, name)
                else:
                    setattr(manager_class, name, original)
            delattr(manager_class, MARK)
            pushes.clear()

    return undo


def serve_every_profile_in_host() -> Callable[[], None] | None:
    try:
        from hermes_cli.plugins import PluginManager
        from hermes_cli.profiles import get_active_profile_name
    except Exception:
        return None
    return serve_every_profile(PluginManager, get_active_profile_name)
