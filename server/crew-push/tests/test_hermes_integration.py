import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

from conftest import PLUGIN_ROOT

HERMES_SRC = os.environ.get("CREW_PUSH_HERMES_SRC", "")

pytestmark = pytest.mark.skipif(not HERMES_SRC, reason="set CREW_PUSH_HERMES_SRC to a Hermes source tree")


def test_plugin_loads_in_hermes(tmp_path: Path) -> None:
    home = tmp_path / "home"
    shutil.copytree(PLUGIN_ROOT, home / "plugins" / "crew-push",
                    ignore=shutil.ignore_patterns("tests", "__pycache__", ".pytest_cache"))
    (home / "config.yaml").write_text("plugins:\n  enabled:\n    - crew-push\n")
    (home / "profiles" / "beta").mkdir(parents=True)
    data = home / "plugin-data" / "crew-push"
    data.mkdir(parents=True)
    key = ec.generate_private_key(ec.SECP256R1())
    (data / "AuthKey.p8").write_bytes(key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    (data / "apns.json").write_text('{"key_id": "ABC123DEFG", "team_id": "82K3YC8HVF", "topic": "dev.gustaf.crew"}')

    env = {"PATH": os.environ["PATH"], "HOME": str(tmp_path), "HERMES_HOME": str(home), "PYTHONPATH": HERMES_SRC}
    run = subprocess.run([sys.executable, str(Path(__file__).with_name("hermes_driver.py"))],
                         env=env, cwd=tmp_path, capture_output=True, text=True, timeout=180)
    line = next((line for line in run.stdout.splitlines() if line.startswith("RESULT ")), None)
    assert line, run.stdout + run.stderr
    result = json.loads(line.removeprefix("RESULT "))

    assert all(result["has_hook"].values())
    assert any("CrewPush.on_session_end" in name for name in result["own_callbacks"])
    assert result["mounted"] is True
    assert result["status"]["plugin_version"] == "0.4.4"
    assert result["status"]["apns_configured"] is True
    assert result["status"]["http2"] is True
    assert result["register"] == 200
    assert result["beta_is_separate_manager"] is True
    assert result["beta_own_callbacks"] == 0
    assert result["pushes"] == [
        {"profile": "default", "session_id": "launch-session", "body": "Done."},
        {"profile": "beta", "session_id": "beta-session", "body": "Done."},
    ]
    assert result["status"]["features"] == ["payments"]
    assert result["shop"] == {"status": 201, "card": {"label": "Shopping card", "last4": "4242", "problem": None},
                              "hosts": ["www.zalando.se"], "label": "Shopping card •••• 4242 · www.zalando.se",
                              "same_secret": True, "gate": False}
    assert result["pay"] == {"gate_off": "crew_gate_off", "blocked": "crew_missing_details",
                             "no_page": "crew_no_shop_page", "allowed": None,
                             "request_id_matches": True, "state": "approved", "fill": "filled",
                             "crew_payment": "approved", "kinds": ["payment", "payment_resolved"]}
    assert set(result["anonymous"].values()) == {401}
