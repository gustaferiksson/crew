# Set Model for All Bots

Hermes has no live "follow the server's model": a bot with no model pinned runs the process env seed or a cache-only silent default, and the only inheritance is a one-time copy at create (`inherit_launch_model`; Desktop's "gateway default" is `config unset model`). So Crew offers one explicit bulk action: **Set Model for All Bots** pins one chosen model on every bot, once. No follow flag, no new `ui_meta`, no "Server Default" option on existing bots (New Bot keeps its own). Each bot can be changed again in its inspector or chat menu.

## Flow

1. Open the sheet, pick a model with the inspector's `ModelPicker`. Its list is the default bot's `model.options`; a model a given bot can't use is an expected per-bot failure ("not available for this bot", Hermes' message).
2. The sheet is the confirmation: footer "Changes the model on 12 bots. Each can be changed again. Bots in the middle of a turn change too, from their next turn." and a button that names the count, **Set Model for 12 Bots**. No generic alert.
3. Crew sends `profiles.configure {name, model, provider}` (`changeModel`) to each bot in turn, the default bot first. Only if Hermes answers `confirm_required` for the first bot (expensive or data-policy model) an alert shows its message with **Use Anyway** / Cancel; one confirm covers the run, nothing was written before it. A later bot asking again is a per-bot failure.

## Which bots

- The roster is snapshotted at the tap. Included: every bot in the list plus the default bot, also when the default bot is hidden. Skipped: other hidden bots, named in the footer ("Not changed: 2 hidden bots."; Photos' Hidden album model, docs/flows/hide-bots.md: nothing the user can't see is rewritten). Rooms have no model.
- Skip rule and count: a bot whose `profiles.list` `model` and `provider` both equal the pick is skipped and not counted; an unknown model or provider means send it. Count 0 shows "All bots already use <model>." and disables the button.
- Hiding or unhiding mid-run keeps the snapshot decision. Bots added mid-run are untouched and named in the result ("1 bot added during the run, not changed."). A bot deleted mid-run fails with Hermes' "not found".

## Where

Account level, like Sign Out. Mac: Settings > Account, a **Set Model for All Bots…** button in the Sign Out section, sheet attached to the Settings window. iPhone (no Settings screen): the Account menu in BotsView, above Sign Out, sheet from BotsView. Disabled while offline or signing out. Not in the inspector or chat toolbar (they are about one bot).

## Progress and result

- Running: determinate bar, "Changing 4 of 12…", the bot's name below (middle truncation). Cancel is disabled and the sheet can't be swiped away. **Stop** finishes the bot in flight, then halts ("Stopping…" meanwhile). Leaving the app on iPhone, losing the connection or signing out acts like Stop.
- The result is a state of the sheet, not an alert: "Changed 11 of 12 bots." (Stopped adds a heading), up to 3 lines "Couldn't change Vera: <Hermes' message>." then "and N more", the added-bots note, and one remaining-bots list shared by **Try Again** (after failures) and **Continue** (after Stop). Both keep the model and the confirmation and resend only the remaining bots. **Done** closes. All changed: the sheet shows "Changed 12 of 12 bots." with Done. VoiceOver gets one announcement of the result.
- After a run: `store.reload` refreshes the roster; the selected bot's `ModelSwitcher` reloads because BotsView's task is keyed on the bot's model, which also updates the inspector's Model row and the chat toolbar checkmark. The inspector's draft doesn't hold the model, so its autosave can't write the old one back. The bot list shows no model. Open chats may show Hermes' "Switched to <model>" notice row on their next turn, as for any single-bot change (not verified per bot).

## States

Loading `model.options`: picker row empty, button disabled. Empty or failed: "No models available", button disabled. One bot: "Set Model for 1 Bot". Offline: disabled, a run in progress ends as a stop. Long model ids and bot names truncate in the middle on one line; messages wrap. System Form, Menu, ProgressView and alert styling only, light and dark.

## Tests

Unit (`Tests/CrewTests/ModelForAllBotsTests.swift`): order and default first, hidden and already-on-model skipped, hidden default included, partial failure and Try Again, confirm_required, later confirm failure, Stop mid-run, lost connection, bots added mid-run. Real server: `Tests/bot_probe/run.sh model-all` on two throwaway `crew-test-all-*` bots (plus a missing bot for the failure path). Renders: `model-for-all-bots`, `-running`, `-failed`.
