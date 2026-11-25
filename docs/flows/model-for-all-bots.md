# Set Model for All Bots

Hermes has no live "follow the server's model": a bot with no model pinned runs the process env seed or a cache-only silent default, and the only inheritance is a one-time copy when a bot is created (`inherit_launch_model`; Desktop's "gateway default" is `config unset model`, which does not follow anything). So Crew offers one explicit bulk action instead: **Set Model for All Bots…** pins one chosen model on every bot, once. No follow flag, no new `ui_meta`, no "Server Default" picker option. Bots can be changed individually afterwards (inspector and chat menu, unchanged).

## What it does

1. The user opens the action, picks a model with the same `ModelPicker` content the inspector uses, from `model.options` (provider sections, model names).
2. A confirmation says what changes: **"Use <model> for 12 bots?"**, message "Each bot can still be changed afterwards.", buttons **Use Model** and Cancel.
3. Crew applies `profiles.configure {name, model, provider}` to each bot in turn, the same call as `changeModel(of:to:confirmation:via:)`. One bot at a time: Hermes writes each profile's config under its own lock, and a sequence keeps progress, ordering and the failure list simple.
4. If Hermes answers `confirm_required` (an expensive or data-policy model, `confirm_message`), it does so for the first bot before anything is written. Crew shows that message once in the confirmation alert ("Use <model> for 12 bots?" plus Hermes' text) and resends every bot with `confirm_expensive_model: true` only after the user taps Use Model. The pick is never sent confirmed unseen. If a later bot unexpectedly asks, it counts as failed with that message.

## Which bots

- **Included:** every bot in the list (favourites, sections, rows), plus the default bot (it is a normal bot with a normal profile, and it is what a fresh bot copies at create; the model is the same call). Bots already on that model are skipped and not counted.
- **Skipped:** hidden bots. Hiding is a Photos-Hidden-album style "out of the main views" (docs/flows/hide-bots.md); the user did not see them in the list and may have hidden them because they run something deliberate. The confirmation says so when any exist: footer line "N hidden bots are not changed." Unhide a bot to include it. This is the safe side of a bulk write: nothing the user cannot see is rewritten.
- Rooms (groups) have no model of their own, so there is nothing to change.
- The count in the title is the number that will actually change (after skipping bots already on the model). If it is 0 the confirm is replaced by an alert, "All bots already use <model>.", and nothing is sent.

## Where it lives

Apple puts an action that affects the whole account where the account lives, not on a content screen: Mail's account settings, Messages' Settings, and iOS Settings rows that push a page. So:

- **Mac:** Settings window (`SettingsView`), a new section above Sign Out: a **Set Model for All Bots…** button (trailing, like Sign Out…; the ellipsis because it asks for more input). It opens a sheet with the picker and a **Use Model…** continue button, then the confirm.
- **iPhone:** no Settings screen exists, so the account menu in `BotsView` that holds Sign Out gets **Set Model for All Bots…** above it (`cpu`). It presents the same sheet (a sheet is presented from the screen container, per PLAN.md, never from the menu item itself).
- Not in the bot inspector or the chat toolbar: both are about one bot, and a bulk write there would read as a change to that bot.
- One implementation (`ModelForAllBots`, a plain function over the roster and `changeModel`) shared by both entry points; the sheet is one view on both platforms (grouped Form with the picker row, NavigationStack, Cancel, 420 x 360 pt on the Mac like the other sheets).

## Progress and results

- While it runs the sheet stays up and the picker row is replaced by a determinate `ProgressView(value:total:)` with "Changing 4 of 12…", the current bot's name on a second line (truncated in the middle), and the Cancel button reads **Stop** (bots already changed keep the new model; the result says so). The sheet cannot be swiped away while running.
- All done: the sheet closes with no extra alert (the inspector shows the new model; HIG: don't confirm success the user can see). Haptic success on iPhone, as other writes.
- Partial failure: the sheet shows an alert-style result inside the sheet: **"Changed 11 of 12 bots."** and, below, **"Couldn't change Vera: <Hermes' message>."** one line per failed bot (up to 3, then "and 2 more"), buttons **Try Again** (re-sends only the failed bots, same confirmation already given, no second confirm) and **Done**. Hermes' message is shown as returned; the fallback is "The server didn't change the model." (same as `changeModel`).
- Stopped: "Changed 5 of 12 bots." with **Continue** (the rest) and **Done**.
- Connection lost mid-run: the remaining bots count as failed with the connection error; once reconnected, Try Again works.

## States

- Loading: the action is enabled once `model.options` has loaded; while loading the picker row shows a spinner, Use Model… disabled.
- Empty or failed `model.options`: the picker row says "No models available" and Use Model… is disabled; no free-text entry (the per-bot inspector has none either).
- No bots besides the default: the title reads "Use <model> for 1 bot?".
- Offline or reconnecting (`connection.state != .connected`): the Settings button and the account-menu item are disabled; a run in progress turns into the connection-lost case above.
- Long content: model ids and bot names truncate in the middle on one line in the picker, progress and failure lines; the confirm text wraps.
- Light and dark: system Form, Menu, ProgressView and alert styling only.
- Accessibility: progress announces "Changing 4 of 12"; the failure lines are one element each; Dynamic Type wraps instead of clipping.

## Out of scope

A live "follow the server" setting, per-server default model, hidden-bot inclusion, reasoning effort, auxiliary models and the per-chat session model.

## Tests (Phase 2)

Unit, replaying recorded `profiles.configure` replies (applied, `confirm_required`, error, mixed): which bots are chosen (hidden and already-on-model excluded, default included), the title count, partial-failure text, Try Again resends only the failures, Stop keeps the applied ones. Real-server probe on `crew-test` and throwaway `crew-test-*` bots only, never the other profiles (a bulk write there is a config change). Renders: Mac Settings with the sheet, iPhone account menu and sheet (idle, running, partial failure), light and dark.
