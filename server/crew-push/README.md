# crew-push

Hermes plugin that sends APNs notifications to Crew (finished turns, failed turns, approvals, questions, opt-in routines). Design: [`docs/push.md`](../../docs/push.md). Needs Hermes v0.21.7 or later.

## Install (once)

Replace `host` with the SSH name of the Hermes machine and run everything as the user that runs Hermes.

1. **Apple Developer > Identifiers > `dev.gustaf.crew`**: enable Push Notifications.
2. **Apple Developer > Keys > +**: tick *Apple Push Notifications service (APNs)*, environment *Sandbox & Production*, restriction *Team Scoped (All Topics)*. Download `AuthKey_<KEYID>.p8` (you only get one download) and note the Key ID.
3. Copy the key and its config to the host:
   ```sh
   ssh host 'mkdir -p ~/.hermes/plugin-data/crew-push && chmod 700 ~/.hermes/plugin-data/crew-push'
   scp AuthKey_<KEYID>.p8 host:~/.hermes/plugin-data/crew-push/AuthKey.p8
   ssh host 'chmod 600 ~/.hermes/plugin-data/crew-push/AuthKey.p8 && printf %s "{\"key_id\":\"<KEYID>\",\"team_id\":\"82K3YC8HVF\",\"topic\":\"dev.gustaf.crew\"}" > ~/.hermes/plugin-data/crew-push/apns.json'
   ```
4. Copy the plugin into the root profile (one install serves every profile):
   ```sh
   rsync -a --delete --exclude tests --exclude __pycache__ --exclude .pytest_cache \
     server/crew-push/ host:~/.hermes/plugins/crew-push/
   ```
5. Enable it. Enabling admits the plugin, which should install `h2` from its `pyproject.toml` into the Hermes environment:
   ```sh
   ssh -t host 'hermes plugins enable crew-push'
   ```
6. Restart the dashboard and the gateway once (their usual service or launcher), so both processes load the hooks and the profile fan-out.
7. Check it: open `https://<dashboard>/api/plugins/crew-push/status` in a browser that is signed in to the dashboard. It must answer `"apns_configured": true` and `"http2": true`. Then in Crew: Settings > Notifications > Send test notification.

   If `http2` is `false`, the enable did not install `h2` (APNs only speaks HTTP/2, and every push fails with `crew-push: send failed (ImportError)` in the logs). Run `hermes plugins disable crew-push && hermes plugins enable crew-push` to rerun the dependency step and restart. If Hermes runs from a plain virtualenv instead of its managed environment, `uv pip install --python <that venv>/bin/python 'h2>=4.1,<5'` also works.

## Crew builds with push (once)

`./build.sh` signs without the push entitlements by default, because they need a provisioning profile with the Push capability; such builds still work and fall back to local notifications while Crew runs.

1. **Apple Developer > Identifiers > `dev.gustaf.crew`**: enable **Push Notifications** and **Time Sensitive Notifications** (step 1 above covers the first).
2. Sign in to the team account in Xcode > Settings > Accounts, so `xcodebuild -allowProvisioningUpdates` can create the Mac and iOS development profiles.
3. Add `CREW_PUSH=1` to `.env` and run `./build.sh`. The macOS build then signs with `Entitlements/Crew-macOS.entitlements` (`com.apple.developer.aps-environment`, time-sensitive) and lets Xcode fetch the profile. Running from Xcode uses the entitlements always (`Entitlements/Crew-iOS.entitlements` on iOS).
4. `./device.sh` builds, installs and launches Crew on the connected iPhone (unlocked, Developer Mode on).
5. Debug builds register as `sandbox`, Release builds as `production`; the iOS Simulator never gets a usable token, so test on a device and the Mac.

## Updates

Every Crew release attaches `crew-push-<version>.tar.gz` (the plugin is versioned separately; skip this when its version did not change). It extracts to a single `crew-push/` directory:

```sh
curl -LO https://github.com/gustaferiksson/crew/releases/download/v<app version>/crew-push-<version>.tar.gz
tar -xzf crew-push-<version>.tar.gz
rsync -a --delete --exclude tests --exclude __pycache__ --exclude .pytest_cache crew-push/ host:~/.hermes/plugins/crew-push/
```

Then restart as in step 6. Registered devices, the key and `install_id` live in `~/.hermes/plugin-data/crew-push/` and survive reinstalls.

## Routes

All under `/api/plugins/crew-push/`, behind the dashboard login: `GET status`, `POST devices`, `DELETE devices/{token}`, `POST test`, `POST read` (`{token, profile, session_id, read_at}`: a silent push to every other device so they clear that bot's notifications). Shapes are in `docs/push.md` section 4.4.

## Tests

```sh
uv venv /tmp/crew-push-venv && uv pip install --python /tmp/crew-push-venv/bin/python pytest httpx h2 'PyJWT[crypto]' fastapi
cd server/crew-push && /tmp/crew-push-venv/bin/python -m pytest -q
```

APNs is faked (an `httpx.MockTransport` and a local HTTP/2 server); nothing reaches Apple. `tests/test_hermes_integration.py` loads the plugin into a real Hermes source tree in a temporary `HERMES_HOME`. It runs only when `CREW_PUSH_HERMES_SRC` points at that tree and the venv has Hermes's own dependencies (Python 3.14, `uv pip install -r <tree>/pyproject.toml`).

Attribution for the code adapted from hermex-push is in [`NOTICE`](NOTICE).
