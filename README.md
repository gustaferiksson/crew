# Crew

Crew is a native SwiftUI client for [Hermes Agent](https://github.com/NousResearch/hermes-agent) bots on iPhone, iPad and Mac. It talks to `hermes dashboard` over its REST API and WebSocket gateway: chat with every profile on your server, follow tool calls and reasoning live, answer approvals and questions, edit a bot's look, instructions and capabilities, and manage its routines. Optional push notifications come from the bundled `crew-push` server plugin.

## Install

**macOS** (macOS 27 or newer):

```sh
brew install --cask gustaferiksson/tap/crew
```

Or download `Crew-<version>.zip` from the [latest release](https://github.com/gustaferiksson/crew/releases/latest) and move `Crew.app` to `/Applications`. Crew updates itself after that (Crew > Check for Updates…).

**iOS** (iOS 27 or newer): builds are Ad Hoc signed, so they install only on devices registered to the developer account. On a registered device, open [gustaferiksson.github.io/crew](https://gustaferiksson.github.io/crew/) in Safari and tap Install. Crew shows a banner in the bot list when a newer build is out.

## Server requirements

- Hermes Agent 0.21.3 or newer, running `hermes dashboard` behind HTTPS.
- Dashboard authentication turned on with the `basic` (username and password) provider. Crew signs in with the same account as the web dashboard and keeps only the session cookies in the Keychain, never the password.

## Push notifications

Without the plugin, Crew notifies you about finished turns, approvals and questions while it is running. For notifications when Crew is closed, install `crew-push` on the Hermes host: see [`server/crew-push/README.md`](server/crew-push/README.md). Each release attaches `crew-push-<version>.tar.gz`; the plugin is versioned separately from the app.

## Building

You need Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
cp .env.example .env   # set DEVELOPMENT_TEAM for a team-signed build
./build.sh             # macOS app and iOS Simulator build, fails on any warning
./device.sh            # build, install and launch on a connected iPhone (needs DEVELOPMENT_TEAM)
```

Without `.env` the Mac build is ad hoc signed. `CREW_PUSH=1` in `.env` signs with the push entitlements (see the plugin README). Releases are built by `package.sh` in CI; [`docs/release.md`](docs/release.md) describes the pipeline. Design notes and decisions live in [`docs/PLAN.md`](docs/PLAN.md).

## License

MIT, see [`LICENSE`](LICENSE). Parts of `server/crew-push` are adapted from hermex-push; see its [`NOTICE`](server/crew-push/NOTICE).
