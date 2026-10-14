# Releasing Crew

Plan for the first public release (v0.1.0) and every one after it. `[me]` = user action, `[claude]` = agent work. Steps run in order; the `[claude]` parts of sections 2 to 5 are in the repo.

## Shape

One `v*` tag on `main` produces, in one GitHub Release on the public repo `gustaferiksson/crew`:

| Asset | Built by | Consumed by |
| --- | --- | --- |
| `Crew-<v>.zip` (Developer ID, notarized, stapled) | shared `gustaferiksson/macos-release` workflow, unchanged | Homebrew cask `gustaferiksson/tap/crew`, macOS in-app updater |
| `Crew-<v>.ipa` (Ad Hoc, registered devices) + `manifest.plist` | Crew's own `ios` job | GitHub Pages OTA install, iOS in-app update check |
| `crew-push-<plugin v>.tar.gz` | same `ios` job | manual deploy to the Hermes host |

Versions: tag `v0.1.0` sets `MARKETING_VERSION=0.1.0`, the Actions run number sets `CURRENT_PROJECT_VERSION` (the shared workflow's `$VERSION`/`$BUILD`, same as Rinse). Stay on 0.x. `project.yml` keeps `0.1.0`/`1` only as the fallback.

## Decisions baked into this plan

1. **macOS drops the App Sandbox.** The Rinse/tinecast updater swaps the bundle in `/Applications` through a `/bin/sh` child, which a sandboxed app (and its children) cannot do. Rinse's main app is not sandboxed either. Hardened runtime stays, with `com.apple.security.device.audio-input` for dictation. Nothing has shipped, so there is no container migration; the dev Mac signs in once more.
2. **Manual provisioning profiles, no App Store Connect API key.** The shared workflow only imports the Developer ID cert and cannot pass extra secrets into `build:`, but `com.apple.developer.aps-environment` (and the data-protection Keychain) needs an embedded profile on macOS. So the **Developer ID** profile for `dev.gustaf.crew` is committed (`Signing/Crew_DeveloperID.provisionprofile`: no device list, no key, it is embedded in every shipped app anyway). The **Ad Hoc** profile lists device UDIDs, so it lives in a secret and is re-exported when a device is added. Mirrors the existing p12-in-secrets pattern.
3. **OTA hosting on GitHub Pages, not release assets.** itms-services needs the manifest over HTTPS, and release asset URLs 302 to a storage host with `application/octet-stream` + attachment headers, which is unverified for itms-services. Pages serves `manifest.plist`, `Crew.ipa`, the two icon PNGs and an `index.html` install link directly, removing the question. Trade-off: only the latest IPA is OTA-installable; older IPAs stay as release assets.
4. **iOS update check reads the Pages manifest, not `releases/latest`.** The manifest is deployed only after the IPA exists, so the app never offers a build that failed to upload. GET `https://gustaferiksson.github.io/crew/manifest.plist`, compare `items[0].metadata.bundle-version` with `CFBundleShortVersionString` (Rinse's `isNewerVersion`), offer "Install Crew <v>", open `itms-services://?action=download-manifest&url=<that URL>`. On launch and on foreground at most once per 24 h; never in `DEBUG`.
5. **Fresh initial commit instead of a history rewrite** (step 2). The repo is one day old, single author, never pushed.

## Audit result

A full `git log --all -p` audit before publishing found no `.env`, `.env.test`, APNs key material or key id, credentials or other author emails. The server host name and a local path in the docs, and the real enabled-skills list in `Tests/fixtures/profiles.describe.v0.21.7.json`, were scrubbed before the fresh initial commit; `.gitignore` now covers `CLAUDE.md`, `.claude/`, `__pycache__/`, `.pytest_cache/` and `/dist/` without relying on a global ignore.

## Steps

### 1. Apple portal and secrets

1. [me] Developer portal: confirm App ID `dev.gustaf.crew` has Push Notifications and Time Sensitive Notifications (it does for dev builds). Confirm the iPhone(s) are registered (`./device.sh` already registered the dev iPhone).
2. [me] Profiles > +: **Ad Hoc** for `dev.gustaf.crew` with the Apple Distribution cert and all devices, named `Crew Ad Hoc`. **Developer ID** for `dev.gustaf.crew` with the Developer ID Application cert, named `Crew Developer ID`. Download both.
3. [me] Export the **Apple Distribution: Gustaf Eriksson (82K3YC8HVF)** cert as `.p12` with a password. In the 1Password release item, section "Crew iOS release": files `AppleDistribution.p12`, `Crew_Ad_Hoc.mobileprovision`, `Crew_DeveloperID.provisionprofile` and the field "AppleDistribution.p12 password". Done: `Crew Ad Hoc` covers the registered iPhone; `Crew Developer ID` includes `aps-environment` production and time-sensitive.
4. [claude, after your OK] `gh secret set` on `gustaferiksson/crew` from `op read` (same source as rinse/amped/tinecast):
   - reused, same values: `APPLE_CERT_P12`, `APPLE_CERT_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_PASSWORD`, `TAP_GITHUB_TOKEN` (`op://Private/Github/Tokens/homebrew-tap`).
   - new, from section "Crew iOS release": `IOS_DIST_P12` = base64 of file `AppleDistribution.p12`, `IOS_DIST_P12_PASSWORD` = field "AppleDistribution.p12 password", `IOS_ADHOC_PROFILE` = base64 of file `Crew_Ad_Hoc.mobileprovision`.
   No App Store Connect API key needed.

### 2. Scrub and publish the source

1. [claude] Apply the audit edits above. Add `dist/`, `__pycache__/`, `.pytest_cache/`, `.claude/`, `CLAUDE.md` to `.gitignore` so the public repo does not depend on the global ignore.
2. [claude] `brew install gitleaks && gitleaks git --redact` and `gitleaks dir --redact` as the mechanical pass; fix anything it finds.
3. [claude] `LICENSE` (MIT, "Gustaf Eriksson", like Rinse); `server/crew-push/NOTICE` stays for the hermex-push-derived code. `README.md`: what Crew is, macOS install (`brew install --cask gustaferiksson/tap/crew`), iOS install (Ad Hoc, registered devices only, link to the Pages install page), server requirements (Hermes >= 0.21.3, dashboard auth), crew-push setup link, building (`.env`, `./build.sh`).
4. [claude] Fresh history: in a new clone, `git checkout --orphan public && git add -A && git commit -m "Crew 0.1.0"` (plain `git commit`, no identity override). Keep the old `main` locally as `archive/pre-public` for the decision trail; it is never pushed.
5. [me] `gh repo create gustaferiksson/crew --public --source . --push` (or let me, if you OK it). Settings > Pages > Source: **GitHub Actions**. Settings > Environments > `github-pages` > Deployment branches and tags: add a tag rule `v*`, otherwise the tag-triggered Pages deploy is refused.

### 3. App changes

1. [claude] macOS: drop `ENABLE_APP_SANDBOX` and `com.apple.security.app-sandbox`, `network.client`, `files.user-selected.read-only` from `Crew-macOS.entitlements`; keep `ENABLE_HARDENED_RUNTIME`, add `com.apple.security.device.audio-input`. Verify dictation, Keychain session and push on the Debug Mac build.
2. [claude] Port `AppUpdater.swift` from Rinse (`releases/latest` HEAD with redirects blocked, `Crew-<v>.zip`, signature requirement `identifier "dev.gustaf.crew"` + team `82K3YC8HVF`, swap on quit or "Install and Relaunch"), macOS only. Hook it into a "Check for Updates…" menu command and an About/Settings row.
3. [claude] iOS update check per decision 4: a small `UpdateCheck` (iOS only) plus a banner/row in the bot list; `UIApplication.shared.open(itms-services URL)`.
4. [claude] Dev builds stamp `MARKETING_VERSION=<git describe>-local` in `build.sh`/`device.sh` (Rinse pattern) so they are distinguishable and never self-update; `DEBUG` skips both checks.
5. [claude] crew-push: bump `dashboard/manifest.json` to match `plugin.yaml`/`pyproject.toml`/`__init__.py` (0.2.0). README "Updates" section: download `crew-push-<v>.tar.gz` from the release, `rsync` into `~/.hermes/plugins/crew-push/` as today. Plugin versions move independently of the app.

### 4. Release scripts

1. [claude] `package.sh <mac|ios>` (keeps `build.sh` the dev script):
   - `mac`: install `Signing/Crew_DeveloperID.provisionprofile`, `xcodegen`, `xcodebuild -configuration Release` (manual signing, identity, profile and `--timestamp` live in the Crew target's Release config in `project.yml`, since command-line overrides also hit the SwiftPM targets), `MARKETING_VERSION=$VERSION CURRENT_PROJECT_VERSION=$BUILD`, copy to `dist/Crew.app`. Check `codesign -d --entitlements` shows `aps-environment production`, audio-input, no `get-task-allow`.
   - `ios`: `xcodebuild archive` for `generic/platform=iOS` (Release), then `-exportArchive` with `ExportOptions-AdHoc.plist` (`method: release-testing`, `signingStyle: manual`, profile `Crew Ad Hoc`, `manifest: {appURL, displayImageURL, fullSizeImageURL}` pointing at Pages), giving `dist/Crew.ipa` + `dist/manifest.plist`. Assert `aps-environment` = `production` in the IPA.
   - icon PNGs 57 and 512 px exported once from `Sources/AppIcon.icon` into `pages/` (committed), with `pages/index.html` holding the install link.
   - The Ad Hoc profile comes from `IOS_ADHOC_PROFILE_PATH` (CI) or `.secrets/Crew_Ad_Hoc.mobileprovision` (local, gitignored). `Signing/Crew_DeveloperID.provisionprofile` is a copy of the 1Password file.
2. [claude] [me to run once locally] `./package.sh mac` + Rinse-style notarize to smoke-test signing before CI.

### 5. Workflows

1. [claude] `.github/workflows/ci.yml` (PRs and `main`): job on `xcode-27`: `brew install xcodegen`, `./build.sh` (ad hoc, no `.env`, zero warnings enforced already). Job on `ubuntu-latest`: `pytest server/crew-push/tests` (the Hermes integration test skips without `CREW_PUSH_HERMES_SRC`), plus a check that the four plugin version strings agree.
2. [claude] `.github/workflows/release.yml` on `v*`, `permissions: contents: write, pages: write, id-token: write`:
   - `macos`: `uses: gustaferiksson/macos-release/.github/workflows/release.yml@main`, `secrets: inherit`, `name: Crew`, `app: dist/Crew.app`, `cask: crew`, `runner: xcode-27`, `signed_by_build: true`, `build: brew install xcodegen && ./package.sh mac`. It creates the release and bumps the cask.
   - `ios`: `needs: macos` (the shared workflow's `gh release create` fails if the release already exists), `runs-on: xcode-27`: import `IOS_DIST_P12` into a temp keychain (same snippet as the shared workflow), install `IOS_ADHOC_PROFILE`, `./package.sh ios`, `gh release upload` the IPA (as `Crew-<v>.ipa`), `manifest.plist` and `crew-push-<plugin v>.tar.gz` (`git archive HEAD:server/crew-push`), then `actions/upload-pages-artifact` + `actions/deploy-pages` with `pages/` + `Crew.ipa` + `manifest.plist`.
   - If `ios` fails after `macos` succeeded: fix and "Re-run failed jobs"; iOS users simply see no update until Pages updates.
3. [claude] Tap: add `Casks/crew.rb` to `gustaferiksson/homebrew-tap` (copy `rinse.rb`: placeholder version/sha, `url .../download/v#{version}/Crew-#{version}.zip`, `auto_updates true`, `depends_on macos: :golden_gate`, `zap trash: ["~/Library/Preferences/dev.gustaf.crew.plist", "~/Library/Application Support/Crew", "~/Library/Caches/dev.gustaf.crew"]`). [me] OK the tap push.

### 6. First release

1. [me] `git tag v0.1.0 && git push origin v0.1.0`, then `gh run watch`.
2. [claude] Verify: release has zip, ipa, manifest, tarball; cask bumped; `brew install --cask gustaferiksson/tap/crew` launches, Gatekeeper-clean.
3. [me] On the iPhone, open `https://gustaferiksson.github.io/crew/` in Safari, tap Install. Sign in, get a push (production APNs). Then tag `v0.1.1` with a trivial change and confirm the in-app "Install" banner and the Mac "Install and Relaunch" both work.
4. [me] crew-push only when its version changed: download the tarball, deploy per its README, restart Hermes.

## Development flow

From the first push on, `main` only moves through pull requests.

- One branch per change (`git switch -c <short-name>`), small and focused; `gh pr create` when it builds locally.
- CI (`ci.yml`: `./build.sh` on `xcode-27`, crew-push pytest and the plugin version check on Ubuntu) must be green; the orchestrating agent then merges (`gh pr merge --squash --delete-branch`).
- Verification stays targeted as in `CLAUDE.md`: zero-warning `./build.sh`, only the affected snapshots, only the probes for the logic touched.
- Releases are cut by the user: `git tag v0.x.y && git push origin v0.x.y` on a green `main`. Versions stay on 0.x.

## Living with dev builds

- **iOS:** `./device.sh` (Debug, Apple Development, sandbox APNs) and the Ad Hoc install share `dev.gustaf.crew` and team, so each install replaces the other in place and keeps data and the Keychain session. On the next connect `PushCenter` re-registers with the new environment (its fingerprint includes it); the plugin routes each token by its stored environment and prunes the stale one on the first `BadDeviceToken`/`Unregistered`. No plugin change needed. To go back to the release, reinstall from the Pages link; a dev build never shows the update banner.
- **macOS:** the dev app in `.build/…/Debug/Crew.app` and `/Applications/Crew.app` share the bundle id; both register for push (sandbox vs production), so a notification may land on either and LaunchServices may open either. Quit one while testing the other; `build.sh`'s `lsregister -f` makes the dev copy win until the release one is launched again.

## Maintenance

- New iPhone/iPad: register in the portal (or `./device.sh` once), regenerate the Ad Hoc profile [me], update `IOS_ADHOC_PROFILE` [claude], tag a release; already-installed devices are unaffected.
- Distribution and Developer ID certs and the Developer ID profile expire: renew, re-export to 1Password, refresh the secrets and the committed profile.
- The public IPA embeds the Ad Hoc profile, so registered device UDIDs are readable by anyone who downloads it. Low risk, but that is the cost of public OTA hosting.

## Resolved questions

- Developer ID + Time Sensitive Notifications: the `Crew Developer ID` profile grants `com.apple.developer.usernotifications.time-sensitive`, so macOS keeps it in `Crew-macOS.entitlements`.
