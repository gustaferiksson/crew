# Pinned card widget: a bot's pinned card on the Home and Lock Screen (#344)

The pinned card (`docs/flows/pinned-card.md`) keeps a bot's newest card one tap away inside its chat. A shopping list or a recipe is also what the user wants at a glance without opening Crew: "Groceries, 2 of 6" on the Lock Screen while standing in the shop. New: a WidgetKit widget that shows the pinned card of a chosen bot, and opens that chat on a tap. Model: Reminders' list widget (a list's name and "3 of 8" progress) and Notes' folder/note widget (one chosen thing, configured by Edit Widget).

## Apple's precedent

- **Reminders:** Home Screen widget per list (chosen with Edit Widget), Lock Screen circular and rectangular with the list's count; a tap opens that list.
- **Notes:** the small widget shows one note's title and first lines; a tap opens the note.
- **Configuration:** `AppIntentConfiguration` with a `WidgetConfigurationIntent` parameter, edited from the system's Edit Widget sheet (long-press the widget). No in-widget settings.
- **Data:** WidgetKit timelines from a shared App Group container; the app calls `WidgetCenter.reloadTimelines(ofKind:)` when its data changes (Apple's "Keeping a widget up to date"). No periodic refresh, no network in the widget.

## Configuration

- **Bot** (optional, `BotEntity`, the same entity and query the Talk to Bot control uses, so the picker lists the same bots from `voice-bots.json`).
- **Not chosen (default):** the most recently pinned card of any listed (not hidden) bot (the time its glance first appeared, not its last tick, so the default doesn't jump between bots while the user ticks cards in two chats). So a freshly added widget shows something useful, like Reminders' default "Reminders" list.
- Rooms (group chats) are not offered: their pins are keyed `group:<id>` and the entity lists bots only. A room's pin never shows in the default either.

## Surfaces

- **Home Screen, small (`systemSmall`):** top row: the card's symbol in its tone's gradient tile (rounded rectangle, the preview tile's look) leading, the bot's avatar (24 pt) trailing. Below, bottom-aligned: the card's title (`.headline`, up to 3 lines), then "2 of 6" (`.subheadline`, secondary, monospaced digits) when the card has a checklist, then the bot's name (`.caption`, secondary, one line). System background (`containerBackground(.background, for: .widget)`), standard content margins.
- **Lock Screen, rectangular (`accessoryRectangular`):** line 1 the card's symbol (`widgetAccentable`) and title (`.headline`, one line); line 2 "2 of 6", else the card's subtitle, else nothing; line 3 the bot's name (secondary). Plain symbol, no coloured tile: Lock Screen widgets render vibrant/tinted.
- **Lock Screen, circular (`accessoryCircular`):** with a checklist, a `Gauge` in `.accessoryCircularCapacity` from 0 to total whose current value label is the card symbol over the done count (the capacity style shows only that label); without one, the symbol on `AccessoryWidgetBackground`.
- **Lock Screen, inline (`accessoryInline`):** the card symbol and "Groceries 2 of 6" (or just the title), one line above the clock.
- **Medium and large:** not in this slice. Reminders' medium and large widgets list the items, and for a shopping list the items are the glance; that needs the rows in the glance and is a follow-up (`systemMedium`).
- **StandBy and iPad:** `systemSmall` covers StandBy; the same families work on iPad.
- **Tap:** every family carries `widgetURL(crew://chat/<bot>)`, the deep link the voice Live Activity already uses (`PushRoute(url:)`), so the bot's chat opens with the pinned chip above the composer; one more tap shows the live card. Opening the card's sheet straight from the widget needs a new route that presents it on arrival; a follow-up, since the chat is the card's home (Reminders opens the list, Notes the note). Accessibility: the widget's label is "<title>, <bot>, 2 of 6 done" (the chip's wording).
- **In Crew:** nothing changes. The chip, its sheet and the transcript card stay as they are; the widget is a read-only mirror.
- **Bot list, push, inspector:** unchanged; the widget adds no notification and no badge.
- **Mac:** not in this slice. `CrewWidgets` is an iOS-only extension, and a macOS widget needs a macOS widget extension target, the App Group on the Mac app (not in `Crew-macOS.entitlements`) and a new Developer ID provisioning profile in the portal. Recorded as a follow-up, not built.
- **Light/dark and rendering modes:** system colours and materials; the tone gradient tile reads on both. Lock Screen families take the system's vibrant rendering, and the Home Screen's tinted and clear styles and StandBy's night mode use the accented mode: the tile's symbol is `widgetAccentable`, the tile and avatar fall back to the system's desaturated treatment. These modes can't be set from the app's snapshot host, so they are checked on a device through a release.

## Data flow

- **Snapshot:** `PinnedGlance` (`surface`, `title`, `subtitle`, `symbol`, `tone`, `progress` (done, total), `pinnedAt`), plain strings and numbers so the widget extension needs neither A2UI nor the card's JSON. One file in the App Group container, `Library/Application Support/pinned-cards.json` (not `Caches`, which the system may purge, blanking the widget), `{chat key: glance}`.
- **Writer:** `ChatPins` owns it, because it already decides what is pinned. `ChatView` hosts a small observer of the pinned surface's model (present whenever the chat has a pinned card in its transcript, also while a request card or Reply chip hides the chip), which reports the card's current summary (`CardSummary`: title, subtitle, symbol, tone, checklist) through `ChatPins.show(_:in:)` on appear and whenever it changes (equality-guarded, so a streaming token writes nothing). So ticks made in the sheet while a reply is pending still reach the widget. `ChatPins` keeps the glance next to the pin in `pins.json` and, on every save, writes the widget file from all chats whose glance matches their pinned surface. So every path that changes the pin removes a stale glance without its own code: unpin (chip X, sheet, context menu, Mac menu), a newer card replacing the pin, pinning another card by hand, bot delete (`clear`) and Sign Out (`reset`, which empties the file). It reloads the widget's timelines only when the file's content changed. `BotStore` also reloads them whenever it rewrites `voice-bots.json` (a rename, a new avatar, a bot hidden or deleted, possibly from another device), so a hidden bot's card leaves the default at once.
- **Mac:** `ChatPins` gets no widget file on macOS (resolving a group container the Mac app isn't entitled to can show a privacy prompt), so the Mac never touches it.
- **File protection:** the default (`completeUntilFirstUserAuthentication`), so the widget reads it while locked; before the first unlock after a restart the read fails and the widget shows "No pinned cards".
- **Reader:** the widget's `AppIntentTimelineProvider` reads the file and `voice-bots.json`, picks the glance (chosen bot, or the default rule) and returns one entry with policy `.never`; the app's reloads drive it. `placeholder(in:)` is the fictional sample, which the system draws redacted; the gallery preview (`context.isPreview`) shows the fictional sample ("Groceries, 2 of 6" from "Chef") instead of an empty state or the user's own card. Display name "Pinned Card", description "A bot's pinned card, like a shopping list or a recipe."

## States

- **Pinned card with a checklist:** title, "2 of 6", bot. Ticking a box in the open chat updates the chip, then the widget (WidgetKit's reload budget does not apply while the app is in the foreground).
- **Pinned card without a checklist:** title and bot, no count; the circular family shows the symbol.
- **No pinned card for the chosen bot** (never pinned, unpinned, or the pin's card not yet seen since this version): the bot's avatar and name over "No pinned card" (secondary); circular shows the `pin.slash` symbol, inline "No pinned card".
- **Default with no pinned cards anywhere:** "No pinned cards" with the `pin` symbol and "Pinned cards from your bots appear here."
- **Chosen bot deleted or hidden after choosing:** a deleted bot is not in `voice-bots.json`, so the widget shows "Choose a bot" (Edit Widget fixes it); a hidden bot that was chosen explicitly still shows (the control's rule).
- **Signed out:** Sign Out empties `pinned-cards.json` and `voice-bots.json`, so the widget shows "Open Crew to sign in." No card title survives on the Lock Screen.
- **Stale:** the widget shows the card as Crew last saw it. A card the bot updates or a new card that arrives while Crew is closed (a push) does not reach the widget until that chat is opened in Crew; there is no background fetch. A new card replacing the pin removes the old glance at once (`arrived`), but the new card's glance appears only when its chip first renders. Accepted for this slice; the widget never shows a card the user has unpinned.
- **Gone from the transcript** (Start New Chat, Compact Chat): the chip hides but the pin and its glance stay, so the widget keeps showing the last card until a newer card replaces it or the user unpins. Accepted: the card still exists in the old session, and the chat it opens is the bot's.
- **Long content:** title truncates (3 lines small, 1 line rectangular and inline); large counts ("120 of 150") stay on one line with the title truncating first.
- **Error:** an unreadable or missing file is treated as "no pinned cards"; nothing throws into the widget.
- **Privacy:** card titles are user content on the Lock Screen, like Reminders' list items. The widget marks the title, subtitle and count `privacySensitive()` (the symbol and bot name stay), so they redact when the user turns off Lock Screen widget data while locked.
- **Dynamic Type, Reduce Motion:** text styles scale; nothing animates beyond the system's widget transitions.

## Card timers on the Lock Screen (layer 3): owned by #338

A running card timer's Lock Screen countdown and Dynamic Island are #338's: AlarmKit schedules the alarm (breaking through the silent switch, which the current notification does not) and brings its own system countdown Live Activity, so a Crew `ActivityConfiguration` for timers would duplicate it and be removed with #338. This slice adds no timer Live Activity; PLAN.md's "Known limitation" on Card timers stands until #338.

## Verification

- Unit (`ChatPinsTests`): the widget file holds a shown glance; unpin, a newer card, pinning another card, `clear` and `reset` each remove it; a glance for a surface that isn't pinned is ignored; a second `ChatPins` on the same files keeps other chats' glances; the fixture store and a store without a widget URL write nothing. Widget choice (`PinnedWidgetContent`): chosen bot, default most recently pinned among listed bots, a ticked card doesn't change the default, hidden or removed bots dropped from the default, room keys ignored, deleted bot, signed out. Each shown failing without the change.
- Renders: `./snapshot.sh ios widget-pinned-card widget-pinned-card-empty` hosts the small, rectangular, circular and inline views for a checklist card, a card without a checklist, no pinned card, no pinned cards, signed out and the privacy-redacted card, light and dark, on a private simulator. Fictional fixture data only.
- Real server: not in this slice. The simulator build is unsigned (`CODE_SIGNING_ALLOWED=NO`), so the App Group container and the widget's reload can't be exercised end to end there; the unit tests cover `ChatPins` writing and the widget's reader on the same file and format.
- Not verifiable off-device or unsigned: the real Home and Lock Screen chrome, the Edit Widget picker and the reload after a tick. They ship for checking through a tagged release.
