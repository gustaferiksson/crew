# Card timer: a tap-to-start countdown in a card (#227)

A recipe step like "Simmer 8 minutes" today is only text; the cook sets a timer somewhere else. New: the step carries its own timer, started with one tap, that keeps counting when the user leaves the chat or Crew, and ends with a notification. The same timer exists as a standalone component for waits outside a recipe ("pizza in the oven, 12 min").

## Payload (skill `crew-ui` version 10)

```json
{"id": "method", "component": "Steps", "items": ["Brown the mince.", {"text": "Add the tomatoes and simmer 8 min.", "seconds": 480}, "Season and serve."]},
{"id": "pizza", "component": "Timer", "label": "Pizza", "seconds": 720}
```

- **Steps item:** a string as before, or `{"text", "seconds"}`. The step reads exactly like a string step and draws a timer row under its text. The timer's name is "Step 2" (its number).
- **`Timer` (`crew/v1`):** `label` (string, optional, defaults to "Timer"), `seconds` (number, required). For a wait that isn't a method step.
- **Plain values only**, no bindings: the bot writes a label and a duration, nothing else, so a model can't get the state wrong. A missing, zero or negative `seconds` on a Steps item draws the step without a timer; on a `Timer` it draws nothing.
- **Skill v10:** one line on each, and the pancakes example's second step becomes a timed step ("let the batter rest 10 min", 600 s). The description stays at 59 characters.

## The timer row

- **Look:** one row, Clock-app style. Leading: the remaining time in monospaced digits (`.body.monospacedDigit()`; `8:00`, `1:05:00` from an hour), after the label for a `Timer` component (the step's text already names a step timer). Trailing: the controls, as plain bordered small buttons (`.buttonStyle(.bordered)`, `.controlSize(.small)`; no glass on glass, `docs/flows/tinted-controls-in-glass.md`).
- **Idle:** the full duration and a Start button (`play.fill`, "Start").
- **Running:** the live countdown (`Text(timerInterval:countsDown:)`, drawn by the system, so no per-second view updates) in the tint colour, a Pause button (`pause.fill`) and a Reset button (`arrow.counterclockwise`, icon only, "Reset" as its label).
- **Paused:** the frozen remaining time in secondary colour, Resume (`play.fill`, "Resume") and Reset.
- **Done:** "Done" with a `checkmark.circle.fill` in green, and Reset (back to idle, so the step can be timed again). The row flips from running to Done at the end date through one `TimelineView(.explicit([end]))` refresh, not a ticking state.
- **iPhone:** the card inputs' text styles; the row is at least 44 pt tall so the small bordered buttons keep a 44 pt hit height. **Mac:** the same row, small bordered push buttons, hover and keyboard focus from the system.
- **Light and dark:** system colours only (tint, secondary, green), checked in both.
- **Reduce Motion:** nothing in the row animates: the digits are the system timer text, and state changes swap the row without a transition, with or without Reduce Motion.
- **Dynamic Type:** text scales; at accessibility sizes the row stacks the time over the buttons (`ViewThatFits`), so the digits never truncate.

## Behaviour

- **Start:** saves the end date (now + `seconds`) and schedules a local notification at that date. Nothing goes to the bot or the server.
- **Pause:** saves the remaining time and removes the pending notification. **Resume:** a new end date (now + remaining) and a new notification. **Reset:** back to idle, removes any pending or delivered notification for this timer.
- **Several timers:** each timer has its own state and notification (identifier: chat key, surface id and timer key), so two steps or two cards can run at once and end separately.
- **Busy turn:** unlike the other card controls, a timer stays usable while the bot replies (a turn takes about 30 s, and a cook must be able to pause): the row re-enables its own buttons inside the surface-wide `.disabled(isBusy)`. Nothing it does reaches the bot, so the reason for the rule does not apply.
- **Streaming:** the progressive preview is the compact row, so timers appear once the card is complete.

## State and persistence

- **Stored in the card's data model**, under a top-level key per timer that the bot never writes: `crew-timer-<component id>` for a `Timer`, `crew-timer-<steps id>-<step number>` for a step (`/` and `~` in ids replaced by `-`). One string value per timer: `running <end, seconds since 1970>` or `paused <remaining seconds>`; `null` or absent is idle.
- **Persisted by `CardState`** (`docs/flows/interactive-cards.md` > Reload, relaunch and switching chats) like any other user write: leaving the chat, relaunching and the iPhone app being killed in the background keep the timer. A running timer whose end date passed while Crew was closed opens as Done; a paused one opens paused at the same remaining time.
- **Expanded row and pinned sheet** share one view model, so a timer started in one shows running in the other.
- **Other Conversations sheet:** no chat key, so the state is not saved (as for ticks); its notification still fires.
- **Bot updates:** the bot never writes `crew-timer-*` keys, so every `updateDataModel`, with or without a path, keeps the timers (`CardState.botUpdated` never drops them, and the replay after the update brings them back into the live model). A same-id re-create ("make it for 6") is a new card: its timers start idle, like its ticks, while a notification the old card scheduled still fires (the user started a real timer; Crew does not cancel it behind their back). Starting the same timer on the new card replaces that notification (same identifier).
- **Cleared:** deleting the bot and Sign Out clear `CardState` (as for ticks); pending timer notifications stay and fire.
- **Done stays** on the card until Reset, also days later, like a ticked box.
- **Per device and per window:** state is per device (a timer started on the iPhone is idle on the Mac), and two Mac windows on one chat have their own `SurfaceStore`, so the second window shows the timer as it was when it opened; Start there replaces the notification (same identifier).

## Notification

- **When:** at the end date, from the system, whether Crew is in the foreground, in the background or not running. `userInfo.crew.kind` is `timer`, and `PushCenter`'s foreground presentation always shows a timer as a banner with sound, also while its own chat is open (other Crew notifications are suppressed for the visible chat). Interruption level `timeSensitive` (the iOS entitlement already exists for approvals), so it breaks through a Focus like Clock's timers do.
- **Text:** title the card's Header title ("Pancakes"), body "Time's up: <what>", where <what> is the step's own text for a step timer ("Time's up: Whisk in the rest of the milk…", the system truncates) and the label for a `Timer` ("Time's up: Pizza"), so it reads on the Lock Screen away from the card. Default sound, thread `timer.<chat key>` so a card's timers group together. A card without a Header title uses "Timer". No hidden-previews category (a recipe step is not private).
- **Tap:** opens Crew on that chat (`userInfo.crew.profile` = the chat key, the existing `PushRoute` open path). No chat key (Other Conversations): opens Crew.
- **Permission, in context:** Crew already asks on first connection (`AppTasks` runs `PushCenter.authorize()`), so usually the answer is known. If it is still `.notDetermined` (asked before any connection, or the request never ran), Start or Resume runs that same `authorize()` (alert, sound, badge; it also registers for push, as at first connection), so the system prompt appears right after the tap that needs it. The timer starts whether the user allows or not.
- **Provisional:** delivered quietly to Notification Center, the system's rule.
- **Denied or off, or `add` fails** (iOS keeps at most 64 pending local notifications): the timer runs and shows Done in the card; no notification, and no nag (the Notifications settings screen already explains how to turn them on).
- **Known limitations:** a plain notification follows the silent switch (Clock's alarms don't), and a running timer has no Lock Screen or Dynamic Island countdown and is hidden while its card is collapsed. AlarmKit or a Live Activity is what Apple would use; PLAN.md keeps Live Activities to voice, so this stays a notification for now.
- **Mac:** the same `UNUserNotificationCenter` request and permission; the banner shows in Notification Center.

## VoiceOver and accessibility

- The time and the label form one element: label "<timer name> timer" ("Pizza timer", "Step 2 timer"), value the remaining time spoken by the system timer text ("7 minutes, 42 seconds"), "Paused, 3 minutes" when paused, "Done" when done.
- The buttons stay their own elements (Start, Pause, Resume, Reset) and are also custom actions on the time element, so a VoiceOver user can start or pause from the time without moving focus.
- A step's text stays one element as before; its timer row follows it as a separate element.
- Checked with `axe describe-ui` on the iPhone render.

## Surfaces and directions

- **Transcript, iPhone and iPad:** the compact preview row is unchanged; timers live in the full card (expanded row, card sheet). **Mac:** the row expands in place with the timers inside.
- **Pinned chip:** unchanged (Header only). The chip's sheet shows the live timers.
- **Bot to user only:** a timer never sends `<a2ui-action>`; the bot doesn't know a timer runs.
- **Bot list preview, push from the server, inspector, Siri:** unchanged (the block is code; `BotAnswer.speech` drops it).
- **Rooms:** the same `SurfaceBlock`, keyed by the room.
- **Hermes Desktop, Hermex, older Crew builds:** the block shows as code (other apps) or as "Couldn't display this card" with the raw block (older Crew: unknown `Timer` component or an object Steps item fails schema validation); the prose carries the recipe. Same accepted degradation as the Stepper.

## States

- **Offline:** works the same; nothing goes to the bot.
- **Long content:** a long `label` wraps; the time and buttons stay trailing until accessibility sizes, where they stack.
- **Very long or odd durations:** hours show as `1:05:00`; fractions of a second round down to whole seconds; `seconds` over 24 h still counts (no cap needed, a local notification takes any interval).
- **Device clock change:** the end date is absolute, so a manual clock change shifts the countdown like Clock's timer would not; accepted, rare.

## Verification

- Unit tests (`CardTimerTests`, each shown failing without the change): the state math (start, pause, resume, reset, the remaining time at a given now, a running timer past its end is Done) with an injected clock; the notification request (identifier, title, body, `timer` kind, time-sensitive, trigger at the remaining time); a whole-model bot update keeps a saved timer; persistence through `CardState` and `SurfaceStore` from one scratch file (start one timer, pause a second, relaunch both stores, find both states; relaunch past the end date gives Done); the skill's recipe example decodes with its timed step.
- Probe: `Tests/chat_probe/run.sh a2ui-unasked` with 2 recipe prompts, each on a fresh throwaway `crew-test` clone with skill v10: count replies with a timed step and check each card builds in Crew's processor. Reported as measured.
- Renders: `chat-a2ui-timer` (a recipe card expanded with step timers idle, running, paused and done, seeded from an in-memory `CardState`) on iPhone and Mac, light and dark.
- No UI test: the state and the request are unit-tested; adding the request and removing it are single system calls.
