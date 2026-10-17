# Tests

| Layer | Where | Run |
| --- | --- | --- |
| Unit and scenario replay (macOS, unhosted) | `Tests/CrewTests` | `xcodebuild test -project Crew.xcodeproj -scheme CrewTests -derivedDataPath .build -destination 'platform=macOS,arch=arm64' -skipPackagePluginValidation -skipMacroValidation` |
| crew-push hooks | `server/crew-push/tests` | `cd server/crew-push && python -m pytest -q` |
| UI interactions (iOS Simulator only) | `Tests/CrewUITests` | `Tests/ui.sh` (`IOS_SIMULATOR=<name>` picks another iOS 27 device) |
| Real-server probes | `Tests/chat_probe`, `Tests/bot_probe` | `Tests/chat_probe/run.sh <phase>` |

CI runs all but the probes.

## Scenarios

A scenario is one real flow recorded once from the server into `Tests/fixtures/scenarios/<name>/`, then replayed offline through the model code each surface uses.

| File | Read by |
| --- | --- |
| `profiles.before.json`, `profiles.during.json`, `profiles.after.json` | `BotStore` roster: time label, unread, server preview (`profiles.list`, only the bots in the flow) |
| `active_list.during.json`, `active_list.after.json` | `BotStore` status: Working and Waiting (`session.active_list`, only their sessions) |
| `<bot>.history.json` | the open chat (`Transcript(history:)`) and the crew-push replay |
| `<bot>.preview.json` | the bot row preview (`BotStore.showPreview`, the 20-row window) |

### Record one

1. Put the flow in `Tests/chat_probe/main.swift` under the `record` phase: a new `scenario` name and the steps. Mutate only `crew-test` and a throwaway `crew-test-*` bot, and delete the throwaway on every path.
2. Run `Tests/chat_probe/run.sh record <name>` (needs `.env.test`). It writes the files above with the host, the user and the throwaway's name scrubbed (the throwaway becomes `crew-test-peer`).
   `Tests/chat_probe/run.sh fresh` records `new-bot-chat` (a throwaway's first Bot Chat, with its runtime reaped before the first prompt) and needs no `crew-test`.
   `Tests/chat_probe/run.sh cold-open` records `cold-open` (a throwaway's CLI-style Bot Chat, reaped, then opened and prompted at once, catching `starting` in `session.active_list`) and needs no `crew-test`.
3. Read the files before committing: no other profile (except read-only captures of a real bug, trimmed and with names replaced), no credentials, and the flow did what you meant (a failed delivery or an `ambiguous` `message_agent` result means record again).

### Add the tests

- Swift: a `Tests/CrewTests/<Name>ScenarioTests.swift` that loads the files relative to `#filePath`, then asserts per chat the visible rows and their kinds, and per bot row the preview, time, status and unread, by replaying rosters and live sessions in order through `BotStore.apply(roster:)` and `apply(live:)`. `BotMentionScenarioTests.swift` is the template.
- crew-push: add a case to `server/crew-push/tests/test_scenarios.py` with the bodies each bot should push.
- Assert today's intended behaviour from `docs/PLAN.md` Decisions. When the code on main differs, assert main and name the test after the gap.

## UI tests

`CrewUITests` launches the app with `-snapshot <fixture> -server hermes.example.com -username gustaf`, so it renders fixture data and never touches the network. Find elements by their accessibility labels and values first (print `app.debugDescription` to see them) and add an `accessibilityIdentifier` only for elements you can't otherwise reach. It never runs on the Mac.

## Profiling

`-snapshot chat-mentions -mentionTurns <n>` puts `n` more tagged exchanges in the mention chat. Record it with `xcrun xctrace record --template 'Time Profiler' --device <private simulator> --attach <pid>` while scrolling or typing, and keep the fast checks in `MentionPerformanceTests`.
