# Interactive cards: a servings stepper that rescales a recipe (#227 steps 3 and 4)

A recipe card today is fixed at the servings the user asked for; "make it for 6" costs a new model turn (about 29 s for köttbullar). New: the card carries a servings Stepper, and turning it rescales every ingredient on the device, instantly and without a turn. The same mechanism (a pure catalog function reading the data model) is the base for a Slider driving a Chart later.

## What already works (A2UI package at `4ca7353`, read from source)

- The data model is reactive: `SurfaceViewModel` rebuilds the node tree synchronously on every data change (`CombineLatest` of components and data, `rebuildTree`).
- Input components write back through `DataBinding.set` (`NodeResolver.resolveDynamicNumber` and friends).
- A property whose schema `$ref` ends in `DynamicString`/`DynamicNumber`/`DynamicValue` resolves `{"path"}` and `{"call", "args"}`; function args resolve paths relative to the template item (`DataContext.resolveDynamicValue`). The basic `CheckBox` `label` and `Text` `text` are `DynamicString`, so an ingredient row can already show a computed string.
- Catalogs take custom functions (`FunctionImplementation`), validated per call by name and required keys (`PayloadValidator.validateFunctionInternal`). There is no arithmetic in the basic catalog.

Missing, and added here: a formatting arithmetic function and a Stepper component. Crew's own components keep plain values except where this spec says otherwise.

## Payload (skill `crew-ui` version 8)

```json
{"id": "servings", "component": "Stepper", "label": "Servings", "value": {"path": "/servings"}, "min": 1, "max": 12},
{"id": "list", "component": "Column", "children": {"componentId": "ingredient", "path": "/ingredients"}},
{"id": "ingredient", "component": "CheckBox", "value": {"path": "done"},
 "label": {"call": "scale", "args": {"value": {"path": "amount"}, "unit": {"path": "unit"}, "item": {"path": "item"}, "one": {"path": "one"}, "from": {"path": "/baseServings"}, "to": {"path": "/servings"}}}}
```

with data `{"servings": 4, "baseServings": 4, "ingredients": [{"amount": 500, "unit": "g", "item": "blandfärs", "done": false}, {"amount": 2, "item": "eggs", "one": "egg", "done": false}]}`. `baseServings` is data, not a literal in the component, so a whole-model `updateDataModel` or a re-created card written for another count rewrites both numbers together and never scales twice.

- **`Stepper` (`crew/v1`):** `label` (string), `value` (bound number, required), `min` (default 1), `max` (default 99). Step is always 1: servings, people and portions are whole numbers; continuous values use the basic `Slider`.
- **`scale` (`crew/v1` function, returns a string):** `value` (number), `from` (the servings the amounts are written for, bound to `/baseServings`), `to` (the current servings), optional `unit`, `item`, `one`. Pure and side-effect free (it runs on every rebuild); never throws, so a bad binding never raises the "Couldn't display this card" chip or an expression error.

## Number formatting

The amount shown is `value × to / from`. When `to` equals `from` (the card as the bot wrote it) the amount shows exactly as written (`33 g`, `1.2 kg` in the device's decimal style), so the card never changes the bot's numbers before anyone touches the Stepper. Otherwise Crew owns the rounding so the model can't get it wrong:

- **Fine metric units** (`g`, `ml`, `mg`): whole numbers, rounded to 1 below 20, 5 below 500, 10 below 1000, 50 from 1000 (`375 g`, `1250 g`). No unit conversion (500 g never becomes 0.5 kg): the model's unit stays.
- **Everything else** (`dl`, `cl`, `l`, `kg`, `msk`, `tsk`, `krm`, `tbsp`, `tsp`, `cup`, `burk`, `paket`, any unknown unit): below 10, the nearest of whole plus ¼, ½, ¾, and ⅓, ⅔ only for `dl` and cups where those measures exist (`1½ dl`, `⅔ cup`, `2¼ tsk`; never `⅓ tsk`); from 10, whole numbers.
- **Countable items** (no unit, or `st`, `pcs`): halves below 2 (`1½ ägg`), whole numbers from 2 (`2 ägg`, never `2½`). Below 2 a half matters (1½ eggs is not 1 or 2), as cookbooks and recipe apps (Paprika, NYT Cooking) scale; from 2 a half egg or onion is noise in the dish, so whole numbers read better.
- **Ties round up** (1.25 eggs shows `1½`): a cook is better served by a little more than by running short.
- **Never zero:** a positive amount shows at least the smallest step (¼, or ½ for countables, 1 for fine metric).
- **Fractions, not decimals:** the only digits shown are whole numbers and the Unicode vulgar fractions, so Swedish ("1½ dl") and English ("1½ cups") read right whatever the device locale, with no `,` vs `.` decimal question. No digit grouping (`1250 g`), which reads correctly in both languages.
- **Singular and plural:** `unit` and `item` are written in the plural (`eggs`, `cups`, `lökar`, `klyftor vitlök`) and `one` is the singular phrase that replaces both when the shown amount is 1 or less (`1 egg`, `½ cup milk`, `1 lök`, `1 klyfta vitlök`). The skill requires `one` for every row whose words change with the count, in any language; rows like `ägg` or `dl grädde` that read right at any amount leave it out.
- **No amount** (`salt och peppar`, `to serve`): a missing `value` shows `unit item` alone, never "0".
- **Amounts baked into text** (a bot whose own skill writes "500 g mince" as one label, or `"amount": "500 g"`): the row shows exactly what was written and does not scale. A recipe whose labels are plain strings (`{"path": "name"}`) ignores the Stepper the same way. The skill says a scalable quantity is a number plus a separate unit.
- **Bad servings:** a missing, zero or non-numeric `from` or `to` shows the written amounts unscaled.

## The Stepper

- **Look:** a row with the label leading and the current value trailing, then the system `Stepper` with its label hidden, like a Settings row ("Servings … 4 [− +]"). iPhone: the − / + capsule; Mac: the system up/down arrows. Same text styles as the other card inputs (body label, secondary monospaced value). Inside the glass card it is a plain control (no glass on glass; `docs/flows/tinted-controls-in-glass.md`).
- **Placement:** the skill puts it directly under the Header, above "Ingredients", so the amounts it changes are right below it.
- **Behaviour:** each tap changes the value by 1 within `min...max` (− disabled at `min`, + at `max`, the system behaviour). The ingredient labels update in the same frame; nothing is sent to the bot. No haptic, matching the system Stepper.
- **VoiceOver:** the Stepper is one adjustable element whose label is `label` and whose value is the count (the visible label and number are hidden from VoiceOver and the Stepper carries both, so it reads "Servings, 4, adjustable"; a `LabeledContent` label read "Servings, 4" plus the value 4); swipe up/down changes it, and each ingredient row then reads its new amount ("1½ dl grädde" is spoken as "one and a half"). Checked with `axe describe-ui` on iPhone.
- **Busy turn:** like every surface control, disabled while the chat's last turn runs. A local-only control could stay enabled, but exempting it from the surface-wide rule is a separate change (the Carousel spec defers the same exemption for links).
- **Offline:** works the same; nothing goes over the network.
- **Streaming:** the progressive preview draws it disabled; the labels already show the scaled amounts as the data arrives.

## Surfaces and directions

- **Transcript, iPhone and iPad:** the compact preview row (Header tile, title, subtitle) is unchanged; the Stepper lives in the full card, in the expanded row and the card sheet/popover. The preview subtitle is the Header's plain string, so skill v8 leaves servings out of it ("45 min", not v7's "4 servings · 45 min") and the Stepper is the one place the count shows. Cards written under v7 keep their static count.
- **Transcript, Mac:** the row expands in place with the Stepper inside.
- **Pinned chip and its sheet:** the sheet shows the same `SurfaceViewModel` as the expanded row, so turning the Stepper in the sheet rescales the row too, and the other way round. The chip shows only the Header, unchanged.
- **Bot to user only:** the Stepper never sends `<a2ui-action>`. The bot doesn't learn the local servings; "make it for 6" still works as a refinement (a new card under the same id, per `docs/flows/card-updates.md`). A Button's `context` can pass `{"path": "/servings"}` if the bot needs it.
- **Bot list preview, push, inspector, Siri:** unchanged (prose only; the block is code). Hermes Desktop and Hermex show the block as code; the prose carries the recipe.
- **Rooms, Other Conversations sheet:** the same `SurfaceBlock`, same behaviour.
- **Older Crew builds:** an unknown `Stepper` or `scale` fails the card as "Couldn't display this card" with the raw block. Same accepted degradation as the Carousel (`docs/flows/a2ui-carousel.md`).

## Reload, relaunch and switching chats: what the user set stays

What the user sets on a card (ticks, the Stepper, choice chips, text fields, sliders: every input that writes the card's data model) survives leaving the chat, a relaunch and the iPhone app being killed in the background mid-cooking, per chat and per card. One rule for every input, so a remembered Stepper never sits next to resetting ticks. This replaces the "reset" decision of the first Stepper change (#227's open question on card control state).

- **Store:** `CardState`, an `@Observable` store shaped like `ChatPins`: `cards.json` in Application Support, written atomically on each change (like `drafts.json`, which also writes per keystroke), never `UserDefaults`. Per device, not synced: other devices, Hermes Desktop and the bot still see the values the bot wrote.
- **Key:** the chat key (the pins' key: `bot.id` for a Bot Chat, `room.selectionID` for a room) plus the card's fingerprint, the surface id and a SHA-256 of the block that created it (as `ChatPins`' seen watermark), so the same card from live and from history is one entry.
- **What is stored:** only the data-model paths the user changed and their values (`/meat/0/done: true`, `/servings: 6`), never the bot's data. A change is a data-model write outside `SurfaceStore`'s ingest of a bot block; its paths come from comparing the model before and after the write (leaves of objects and of arrays that kept their length; an array that changed length is stored whole, as a choice list is). A user who unticks a box again keeps that entry (the value equals the bot's, which changes nothing).
- **Bounded:** at most the 200 most recently changed cards across all chats; the oldest goes first.
- **Replay:** after `SurfaceStore.sync` has ingested the transcript's blocks, the saved values of each card are written into its live data model (inside the ingest guard, so replay is not recorded as a change), so the ticks, the scaled amounts and the pinned chip's "3 of 8" are back before the first frame of the reopened chat.
- **Rooms:** same as a Bot Chat, keyed by the room. **Other Conversations sheet:** not saved (it has no chat key, like pins); its cards reset when the sheet closes, as before.
- **Bot list preview, push, inspector, Hermes Desktop, other devices:** unchanged; nothing is sent to the bot or the server.
- **Two Mac windows on one chat:** each `ChatView` has its own `SurfaceStore`, so a tick in one window shows in the other only after it reopens the chat; both write the same entry and the last write wins per path.

## Card updates by the bot

- **Update-only `updateDataModel` with a `path`** (a tick-off, a new count): the bot's value wins for that path and anything below it; every other user value stays (the local servings stay through a tick-off). The entry drops the paths the bot sent, so a relaunch does not bring back the overridden value. Each entry remembers the update blocks it has already seen (their SHA-256), seeded at every user change with the card's update blocks ingested so far, so replaying the same history after a relaunch drops nothing (also for a value the user changed after a tick-off that was already in history), while a later bot update does. A bot path above a saved path (`/meat` over `/meat/0/done`) or below one (`/choices/1` under a whole saved `/choices` array) both count as sent.
- **`updateDataModel` without a path** (whole model): the bot sent every path, so every user value of that card goes; `baseServings` comes with it, so amounts are never scaled twice.
- **Re-create with the same id** ("make it for 6", a new `createSurface` block): a new fingerprint, so the card starts fresh with the bot's servings, amounts and ticks; the older entry is never replayed and ages out of the 200. The "updated below" line of the older turn is unchanged.
- **Identical blocks** (the bot repeats a block word for word): one fingerprint, so one entry, as for pins.

## Cleared

- **Start New Chat and Compact Chat:** after the server confirms, the chat's entries go (the cards leave the transcript; `card-updates.md`). The open `ChatView` keeps its processor, so a card still on screen keeps what the user set until the chat closes. A compaction that changed nothing also clears, so such a card resets on the next relaunch; accepted (rare, and Compact is an explicit fresh start).
- **Deleting the bot:** its entries go, with its draft and pin.
- **Sign Out:** the whole file is reset, at both call sites that reset drafts and pins (`SettingsView`, `BotsView`); the Mac Sign Out text says Crew forgets "the unsent drafts, pinned cards and card choices on this Mac".

## States

- **Offline:** cards and their saved values are local, so they show offline.
- **Busy:** cards are disabled while a turn runs (unchanged), so the user writes nothing then; bot updates during the turn land after it.
- **A saved path the card no longer has** (the bot's update removed a row): writing it adds the key back to the data model, which nothing binds, so nothing shows.
- **Unreadable or missing file:** starts empty, like `pins.json`.
- **Snapshots and tests:** an in-memory store (UI tests may pass a scratch file in the app's temporary directory), never the real `cards.json` (Application Support is shared by Debug and release Mac builds).

## Invalid input and long content

- **Stepper without a bound `value`** (a literal number): shows the number, changes nothing (the package's literal binding ignores writes). The skill always binds it.
- **`value` path missing from the data:** shows `min` and writes the first change.
- **`max` below `min`:** the range collapses to `min`; both buttons disabled.
- **Unknown function name or a `scale` call missing `from`/`to`/`value` keys:** schema validation fails the card as today ("Couldn't display this card" with the raw block). `scale` itself never fails at render time.
- **Long ingredient text:** wraps like any CheckBox label (no truncation). Long Stepper label: wraps on iPhone, the value and control stay trailing.
- **Large servings** (`max` 99, `to` 40 from 4): amounts grow to whole numbers (`5000 g`, `40 dl`); no unit conversion.
- **Dynamic Type:** system controls; at accessibility sizes the label wraps and the value and Stepper stay trailing.

## Slider and Chart (later in this issue, not in this change)

A Slider bound to `/rate` already writes the data model. Driving a Chart needs `Chart.values` to accept a `DynamicValue` and a pure `series`-style function; same mechanism, separate PR.

## Verification

- Unit tests decode the skill's own recipe example and the recorded real-bot card, set `/servings` to several values and assert every ingredient label (each shown failing without the change).
- Unit tests of the formatting table above (metric, fractions, countables, singular, no amount, bad servings).
- Real-server probe on a throwaway clone of `crew-test` (`Tests/chat_probe/run.sh a2ui-servings`): "Give me a recipe for köttbullar for 4" must produce a Stepper and `scale` bindings; the recorded reply becomes a fixture.
- Renders of the recipe card expanded at two servings values, Mac and iPhone, light and dark (the iPhone − / + capsule on glass in both).
- `axe describe-ui` on the iPhone render: the Stepper is one adjustable element with the count as its value.
- Card state (`CardStateTests`, each shown failing without the change): tick a recorded card's box through its CheckBox binding and turn its Stepper, build a new `CardState` and `SurfaceStore` from the same scratch file, replay the same history and find the tick, the servings and the scaled amount; a later bot tick-off overrides only its own path while the user's other values stay, and replaying that history again keeps it so; a same-id re-create starts fresh; `clear` and `reset` empty the file; the 200-card bound drops the oldest.
- Render `chat-a2ui-saved` on the Mac and iPhone, light and dark: the recorded köttbullar card from `Tests/fixtures/chat.a2ui-servings.history.json` expanded with saved ticks and servings replayed from an in-memory store.
- No iOS UI test: the unit tests rebuild both stores from one scratch file, which is what a relaunch does; a UI test would only repeat that through a test-only launch path.
