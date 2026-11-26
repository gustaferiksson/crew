import ast
import os
import sys
from pathlib import Path

import pytest

from conftest import PLUGIN_ROOT
from crew_push.hooks import HOOK_NAMES

HERMES_SRC = os.environ.get("CREW_PUSH_HERMES_PINNED", "")
HERMES = Path(HERMES_SRC)
NOT_HERMES = {"crew_push", "fastapi", "httpx", "jwt", "pydantic", "starlette", *sys.stdlib_module_names}
RETURNED = [
    ("hermes_cli.plugins", "PluginManager", "invoke_hook"),
    ("hermes_cli.plugins", "PluginManager", "has_hook"),
    ("hermes_cli.plugins", "PluginManager", "iter_hook_callbacks"),
    ("agent.vault_store", "VaultStore", "list_items"),
    ("agent.vault_store", "VaultStore", "add_item"),
    ("agent.vault_store", "VaultStore", "remove_item"),
    ("agent.vault_store", "VaultStore", "resolve_secret"),
    ("tools.browser_supervisor_capture", "CapturedCDP", "call"),
    ("tools.browser_supervisor_capture", "CapturedCDP", "page_session_id"),
    ("tools.browser_supervisor_capture", "CapturedCDP", "task_id"),
]

SESSION_DB = [
    ("hermes_state", "SessionDB", "get_session_by_title"),
    ("hermes_state", "SessionDB", "get_compression_tip"),
    ("hermes_state", "SessionDB", "get_session"),
    ("hermes_state", "SessionDB", "get_conversation_root"),
    ("hermes_state", "SessionDB", "close"),
]
PERSISTENCE = [
    ("persistence.core.backend", "PersistenceStore", "sessions"),
    ("persistence.core.backend", "PersistenceStore", "lineage"),
    ("persistence.core.backend", "PersistenceStore", "hosted_rooms"),
    ("persistence.conversation.sessions", "SessionRecord", "session_id"),
    ("persistence.conversation.sessions", "SessionRecord", "source"),
    ("persistence.conversation.sessions", "SessionRecord", "title"),
]
SIGNATURES = [
    ("persistence_assembly", "open_persistence_reader", ["target"], []),
    ("gateway.hosted_rooms", "list_rooms", ["store"], ["placement"]),
    ("persistence.conversation.sessions", "SessionRepository.get_by_title", ["title"], []),
    ("persistence.conversation.sessions", "SessionRepository.get", ["session_id"], []),
    ("persistence.conversation.lineage", "LineageRepository.tip", ["session_id"], []),
    ("persistence.conversation.lineage", "LineageRepository.conversation_root", ["session_id"], []),
    ("persistence.gateway.hosted_rooms", "HostedRoomRepository.list_rooms", [], ["placement"]),
]

pytestmark = pytest.mark.skipif(not HERMES_SRC, reason="set CREW_PUSH_HERMES_PINNED to a Hermes source tree")


@pytest.fixture(autouse=True)
def bot_chat() -> None:
    return None


def plugin_uses() -> list[tuple[str, str, str, str]]:
    uses = []
    for path in sorted(PLUGIN_ROOT.rglob("*.py")):
        if "tests" in path.relative_to(PLUGIN_ROOT).parts:
            continue
        where = str(path.relative_to(PLUGIN_ROOT))
        imported: dict[str, tuple[str, str]] = {}
        tree = ast.parse(path.read_text())
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom) and node.level == 0 and node.module.split(".")[0] not in NOT_HERMES:
                for alias in node.names:
                    uses.append((where, node.module, alias.name, ""))
                    imported[alias.asname or alias.name] = (node.module, alias.name)
            if isinstance(node, ast.Import):
                for alias in node.names:
                    if alias.name.split(".")[0] not in NOT_HERMES:
                        module, _, name = alias.name.rpartition(".")
                        uses.append((where, module, name, ""))
                        imported[alias.asname or alias.name] = (module, name)
        for node in ast.walk(tree):
            if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name) and node.value.id in imported:
                uses.append((where, *imported[node.value.id], node.attr))
    return sorted(set(uses))


def source(module: str) -> Path | None:
    base = HERMES.joinpath(*module.split("."))
    return next((path for path in (base.with_suffix(".py"), base / "__init__.py") if path.is_file()), None)


def top_level(body: list[ast.stmt]) -> list[ast.stmt]:
    nodes = []
    for node in body:
        nodes.append(node)
        if isinstance(node, (ast.If, ast.Try)):
            handlers = [stmt for handler in getattr(node, "handlers", []) for stmt in handler.body]
            nodes += top_level([*node.body, *node.orelse, *handlers, *getattr(node, "finalbody", [])])
    return nodes


def bound_names(node: ast.stmt) -> list[str]:
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
        return [node.name]
    if isinstance(node, ast.Assign):
        return [target.id for target in node.targets if isinstance(target, ast.Name)]
    if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
        return [node.target.id]
    if isinstance(node, (ast.Import, ast.ImportFrom)):
        return [alias.asname or alias.name.split(".")[0] for alias in node.names]
    return []


def binding(module: str, name: str) -> tuple[str, ast.stmt | None] | None:
    qualified = f"{module}.{name}" if module else name
    if source(qualified):
        return qualified, None
    path = source(module)
    if path is None:
        return None
    for node in top_level(ast.parse(path.read_text()).body):
        if name not in bound_names(node):
            continue
        if not isinstance(node, ast.ImportFrom):
            return module, node
        parts = module.split(".")
        package = parts[:len(parts) - node.level + (path.name == "__init__.py")] if node.level else []
        origin = ".".join([*package, *([node.module] if node.module else [])])
        target = next(alias.name for alias in node.names if (alias.asname or alias.name) == name)
        return binding(origin, target) if source(origin) or source(f"{origin}.{target}") else (origin, node)
    return None


def members(module: str, node: ast.stmt | None) -> set[str]:
    if node is None:
        return {name for stmt in top_level(ast.parse(source(module).read_text()).body) for name in bound_names(stmt)}
    if isinstance(node, ast.Assign) and isinstance(node.value, ast.Call) and isinstance(node.value.func, ast.Name):
        cls = binding(module, node.value.func.id)
        return members(*cls) if cls else set()
    if not isinstance(node, ast.ClassDef):
        return set()
    names = {name for stmt in top_level(node.body) for name in bound_names(stmt)}
    names |= {target.attr for function in node.body if isinstance(function, (ast.FunctionDef, ast.AsyncFunctionDef))
              for stmt in ast.walk(function) for target in getattr(stmt, "targets", [getattr(stmt, "target", None)])
              if isinstance(target, ast.Attribute) and isinstance(target.value, ast.Name) and target.value.id == "self"}
    for base in node.bases:
        resolved = binding(module, base.id) if isinstance(base, ast.Name) else None
        names |= members(*resolved) if resolved else set()
    return names


def function_of(module: str, qualified: str) -> ast.FunctionDef | None:
    owner, _, name = qualified.rpartition(".")
    body = top_level(ast.parse(source(module).read_text()).body)
    if owner:
        body = next((top_level(node.body) for node in body if isinstance(node, ast.ClassDef) and node.name == owner), [])
    return next((node for node in body if isinstance(node, ast.FunctionDef) and node.name == name), None)


PERSISTENCE_API = bool(HERMES_SRC) and source("persistence_assembly") is not None
UNUSED = ("hermes_state", "SessionDB") if PERSISTENCE_API else ("persistence_assembly", "open_persistence_reader")
USES = [use for use in plugin_uses() if use[1:3] != UNUSED]
RETURNED_BY_VERSION = RETURNED + (PERSISTENCE if PERSISTENCE_API else SESSION_DB)


def test_hermes_tree_is_present() -> None:
    assert source("hermes_cli.plugins"), f"{HERMES} is not a Hermes source tree"


@pytest.mark.parametrize("where, module, name, attribute", USES,
                         ids=[f"{w}:{m}.{n}{'.' + a if a else ''}" for w, m, n, a in USES])
def test_plugin_uses_exist_in_pinned_hermes(where: str, module: str, name: str, attribute: str) -> None:
    found = binding(module, name)
    assert found, f"{where} uses {module}.{name}, which Hermes no longer has"
    if attribute:
        assert attribute in members(*found), f"{where} uses {module}.{name}.{attribute}, which Hermes no longer has"


@pytest.mark.parametrize("module, name, attribute", RETURNED_BY_VERSION, ids=[".".join(use) for use in RETURNED_BY_VERSION])
def test_returned_objects_keep_their_attributes(module: str, name: str, attribute: str) -> None:
    found = binding(module, name)
    assert found and attribute in members(*found), f"Hermes' {module}.{name} has no {attribute}"


@pytest.mark.skipif(not PERSISTENCE_API, reason="Hermes before 0.23.3 has no persistence interface")
@pytest.mark.parametrize("module, qualified, positional, keyword", SIGNATURES, ids=[f"{m}.{q}" for m, q, _, _ in SIGNATURES])
def test_storage_calls_match_signatures(module: str, qualified: str, positional: list[str], keyword: list[str]) -> None:
    function = function_of(module, qualified)
    assert function, f"Hermes' {module} has no {qualified}"
    arguments = function.args
    assert [arg.arg for arg in arguments.args if arg.arg != "self"][:len(positional)] == positional
    assert set(keyword) <= {arg.arg for arg in arguments.kwonlyargs}


def test_hooks_are_valid_hermes_hooks() -> None:
    plugins = ast.parse(source("hermes_cli.plugins").read_text())
    node = next(node for node in plugins.body
                if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.target.id == "VALID_HOOKS")
    assert set(HOOK_NAMES) <= set(ast.literal_eval(node.value))
