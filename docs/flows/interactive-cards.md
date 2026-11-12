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
- **Countable items** (no unit, or `st`, `pcs`): halves below 3 (`1½ ägg`), whole numbers from 3. Half an egg or onion is how cookbooks and recipe apps (Paprika, NYT Cooking) scale; rounding silently to 2 would change the dish.
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

## Reload, relaunch and switching chats: reset

The Stepper resets to the bot's servings whenever the chat's `SurfaceStore` is rebuilt (leaving the chat, a relaunch, or on iPhone the app being killed in the background mid-cooking; a history reload keeps it, since blocks are keyed by text), exactly like ticks, text fields and chips today. Decision: reset, not persist, in this change.

- One rule for every card input: persisting only servings would leave ticks resetting next to a remembered stepper on the same card.
- Persisting card input belongs in one place for all inputs (a `pins.json`-style file keyed by chat, surface id and block fingerprint, replayed after `ingest`), which is the open question already on #227. It is a follow-up, not part of this change.
- The bot's message stays the source of truth: other devices and other apps see the servings the bot wrote.
- Cost: a user who scaled to 6 and switches chats sees 4 again. Accepted for now; #227's open question on card control state covers it.

## Card updates by the bot

- **Re-create with the same id** ("make it for 6"): a new card with the bot's servings and amounts; local stepper state is gone, like ticks (card-updates spec).
- **Update-only `updateDataModel` with a `path`** (a tick-off): only that path changes; the local servings stay.
- **`updateDataModel` without a path** (whole model): replaces local servings with the bot's, as it replaces ticks; `baseServings` comes with it, so amounts are never scaled twice.

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
