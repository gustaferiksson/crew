import sys
from pathlib import Path
from typing import Any

if (_root := str(Path(__file__).resolve().parent)) not in sys.path:
    sys.path.append(_root)

from crew_push.fanout import serve_every_profile_in_host  # noqa: E402
from crew_push.hooks import HOOK_NAMES, CrewPush  # noqa: E402


def register(ctx: Any) -> None:
    push = CrewPush(profile=getattr(ctx, "profile_name", "") or "default")
    for name in HOOK_NAMES:
        ctx.register_hook(name, getattr(push, name))
    undo = serve_every_profile_in_host()
    if undo is not None:
        ctx.on_unload(undo)
