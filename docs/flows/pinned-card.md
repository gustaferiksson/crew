# Pinned card: the bot's latest A2UI card stays reachable above the composer

A bot's card (a recipe, a route, a comparison) scrolls away as soon as the user asks a follow-up, and they scroll back up to find it (user request 2026-11-01: "pinned until I dismiss it, like a sheet, or a better suggestion"). New: the newest card pins itself as a slim glass bar directly above the composer, like Music's mini player above the tab bar or Maps' pinned route. Tapping the bar shows the whole, live card; the X unpins it. The card also stays where it was in the transcript.

Apple's pattern for "something I keep coming back to while doing something else" is a compact accessory that expands on tap (Music, Podcasts, Maps, a FaceTime call banner), not a card that permanently eats half the chat. A permanent inline copy of a 600 pt recipe card would leave no room for the conversation on an iPhone.

## The pin rule

- **Unit:** one A2UI surface (`surfaceId`). A block that creates several surfaces offers each; the newest is the last one created in transcript order.
- **Auto-pin:** when a new card arrives, it becomes the chat's pinned card and replaces whatever was pinned.
- **Seen watermark:** each chat stores `seen`, the newest card it has already considered: its fingerprint (surface id plus a SHA-256 of the block text, stable between live and history replies; `SurfaceStore` already keys blocks by that text) and its turn's finish time. A card is new only when its finish time is later than `seen`'s and its fingerprint differs. So a relaunch, a history window that briefly lacks the newest reply, room pages arriving newest first, or Compact never re-pin an older or the same card; a transcript with no card changes nothing; and a live card (device time) reloaded from history (server time) is still recognised by its fingerprint. A new `createSurface` reusing an old id ("recipe" again) has a new fingerprint and a later time, so it pins.
- **Old cards never auto-pin:** a chat with no entry starts from `since`, the moment Crew first created the pins file (fresh install, first launch with this feature, or after Sign Out). Opening a chat whose newest card is weeks old shows no bar; a card that arrived while Crew was closed (bot answered, push tapped) is newer than the watermark and pins.
- **Identical blocks:** a bot that repeats a block word for word produces the same fingerprint (and `SurfaceStore` already shows it once), so after an unpin it does not pin again. Accepted.
- **Unpin:** the bar's X, the sheet's Unpin, or the card's context menu clears `pinned`. It stays unpinned until a newer card arrives or the user pins one by hand.
- **Pin by hand:** every card in the transcript has a context menu with Pin Card or Unpin Card. Pinning an older card replaces the current pin; a newer card later still replaces it.
- **Updates:** a later block that only updates an existing surface (`updateComponents`, `updateDataModel`) is not a new card. The bar and the open sheet show the live surface, so a pinned card that updates shows the new title and content immediately and stays pinned (or unpinned).
- **Gone:** if the pinned surface is not in the current transcript (Start New Chat, Compact Chat, the server no longer returns that reply), the bar is hidden; the stored pin is harmless and is replaced by the next card.

## Storage

`ChatPins`, an `@Observable` store shaped like `ChatDrafts`: `pins.json` in Application Support (`{since, chats: {chatID: {seen, pinned}}}`), written atomically on each change, never `UserDefaults` and never `drafts.json` (its decoder expects `[String: String]`, a new shape would drop everyone's drafts). Keys are the drafts' keys: `bot.id` for a Bot Chat, `room.selectionID` for a room. Per device, not synced (like drafts). Cleared for a bot when it is deleted here; reset on Sign Out at both call sites that reset drafts (`SettingsView`, `BotsView`), and Settings' Sign Out text gains "pinned cards". Snapshots and UI tests use an in-memory fixture store and `ChatPinsTests` a temporary file, so neither writes the real file (Application Support is shared by Debug and release Mac builds, like `drafts.json`).

The logic (newest card in, pinned card out) lives in `ChatPins` so `CrewTests` can test it without the A2UI package. `SurfaceStore.sync`, on the existing turn-status sync, walks `transcript.turns` from the end to find the newest rendered card (surface id, block text, turn finish time; not the last ingested block, since older pages can arrive later), using a cached reply-to-blocks map so no markdown is parsed again, and hands it to `ChatPins`. Nothing new runs per streamed token. Two views of one chat (main window and a Mac chat window) feed the same card; the watermark makes that idempotent, and each view has its own open/closed sheet state.

## The bar

- **Where:** in the chat's bottom `safeAreaBar` stack, directly above the composer (or the voice composer while a voice message records) and below any payment, approval, question or shop card. While one of those request cards shows, the bar is hidden (the request needs the attention and the stack would get tall), which closes the card's sheet or popover if open (the pin stays); it comes back when the request is answered.
- **Look:** one row on a Liquid Glass capsule drawn behind the content (`.background { Color.clear.glassEffect(.regular.interactive(), in: .capsule) }`, PLAN's no-glass-in-glass rule, so the tile and text are not turned vibrant), 44 pt high on iOS and 36 pt on Mac: a 28 pt rounded tile with the card's symbol in white on the tone's gradient (the Header tile, smaller), the title in `.subheadline.weight(.semibold)`, one line, tail truncation, then the X (`xmark`, secondary, borderless, its own 44 pt hit area on iOS).
- **Width:** the composer's own side margins (iOS 28 pt with the keyboard hidden, 16 pt while the composer is focused; Mac 16 pt), so the bar spans exactly the composer row (from the `+` to the field's end) like the mini player spans the tab bar, at every window width (a 560 pt centred bar looked detached over the Mac's full-width composer in the first render). Not added to the locked UI values.
- **Title:** the card's first Header `title`; else the first line of its first Text; else "Card from <bot>" ("Card" in a room). Symbol: the Header's `symbol` (through `systemSymbol`, so an unknown name falls back), else `rectangle.on.rectangle`; tone from the Header's `tone`, else the accent colour. Read from the surface's resolved `rootNode`, which only changes when a block is processed.
- **Window minimum (#60):** one line, no `fixedSize`, so the bar never raises the Mac window's minimum height; covered by the offscreen probe.
- **Appearance:** the bar fades in with the composer stack's existing `.smooth` animation.
- **Transcript inset and Jump to Latest:** the bar is inside the bar stack whose height already sets the transcript's bottom inset and the Jump arrow's offset, so the arrow stays 12 pt above the top of the whole stack.

## Opening the card

- **One presentation for every platform:** tapping the bar presents the card with `.popover` anchored to the bar and `.presentationCompactAdaptation(.sheet)`: a popover where there is room (Mac, iPad regular width) and a sheet on iPhone, from one modifier. PLAN's rule (present from the container, never from a `List`/`Form` row) guards against rows SwiftUI recycles; the bar sits in the chat's own bottom bar stack, not in a list, so it is a stable anchor. The UI test asserts the sheet stays open 3 s.
- **iPhone sheet:** tapping the bar dismisses the keyboard first. `.presentationDetents([.medium, .large])` starting at medium, `.presentationBackgroundInteraction(.enabled(upThrough: .medium))`: at medium the user can still scroll and read the transcript above it; the composer is under the sheet, so a follow-up means swiping the sheet down (the bar is still there) or tapping close. Content: the live surface on the sheet's own background (no glass card inside the sheet), in a scroll view, with the card's title as the inline navigation title, a close button (`Button(role: .close)` in the cancellation slot, the plain glass xmark iOS 26 uses on read-only sheets; in the confirmation slot it rendered as a prominent blue confirm) leading and Unpin (`pin.slash`) trailing.
- **Mac and iPad popover:** 440 pt wide, at most 560 pt tall with the card scrolling inside, arrow pointing at the bar; clicking or tapping elsewhere (into the composer) closes it and keeps the pin. Same content with Unpin in a small row at its top and no close button (popovers close by clicking outside or Escape). The Mac inspector was considered and rejected: it is the bot's Info Form (`.inspector` column with locked widths), a card there is foreign and would fight the bot inspector for the column.
- **The card in the sheet or popover** behaves exactly like the transcript copy: its buttons send the same action to the bot, it is disabled while a turn runs, and it is as enabled offline as the transcript copy is today. The sheet stays open after a button tap; the reply streams behind it.
- **Dismissing vs unpinning:** swiping the sheet down, close, Escape, or clicking outside the popover only closes it; the bar stays. Only the X, Unpin, or the context menu unpins (Unpin in the sheet also closes it).
- **The card changes while open:** the sheet follows the surface id, so a follow-up that re-creates the same id ("make it vegan") swaps the content in place and the sheet stays open. It closes only when no surface with that id is left in the transcript. A different newer card replaces the pin and the bar; the open sheet keeps the card the user opened.

## Surfaces and directions

- **Bot Chat, iPhone, iPad and Mac, light and dark:** as above. Light and dark come from the glass and the semantic colours; the tile keeps white on the tone gradient in both.
- **Rooms:** same bar, keyed by the room; any member's card counts as the newest. Title fallback is "Card" (several bots speak). Card buttons in rooms send nothing today (rooms have no hidden send); the sheet matches that.
- **Other Conversations sheet (search result or Info tab):** no bar and no Pin action; it is already a temporary sheet with no stored chat key.
- **Chat windows on Mac (`BotChatWindow`):** the same `ChatScreen`, same key, so the main window and a chat window show the same pin and an unpin in one shows in the other.
- **Bot list preview, time, status, unread, push, inspector:** unchanged. The bar is client-only, sends nothing to the server and changes no row.
- **Sender, receiver, replies back:** the bot sends the card; the user only pins, unpins and taps through. A button tapped in the sheet sends the same hidden action row as in the transcript and the reply streams behind the sheet.
- **Haptics:** a light impact for Pin Card and Unpin by hand (PLAN gives Pin/Hide a light impact); nothing for an auto-pin, a newer card replacing the pin, or opening the sheet.

## States

- **No title:** first Text line, else "Card from <bot>"; no symbol falls back to `rectangle.on.rectangle`.
- **Long title:** one line, tail truncation; VoiceOver reads it whole.
- **Card updates while pinned:** the bar's title and the open sheet follow the live surface; pin state unchanged.
- **Card whose turn failed or was stopped:** if the block parsed and rendered a card, it is a card and may pin; a block that failed ("Couldn't display this card") or a reply that never finished its fence never pins and never shows a bar.
- **Streaming:** nothing happens until the reply finishes (the existing sync point); "Preparing card…" stays in the transcript only.
- **Busy:** while a turn runs the card is disabled in the sheet like in the transcript; the bar itself stays tappable.
- **Offline:** the bar and sheet still open (the card is local); the card behaves like the transcript copy.
- **Empty chat, no cards, Rich UI off:** no card, no bar.
- **Keyboard up (iOS):** the bar rides up with the composer (it is part of the same bar stack) and narrows to the 16 pt margin with it; tapping it closes the keyboard and opens the sheet.
- **Large Dynamic Type:** the bar grows with the text (one line), the tile scales with it; the X keeps its 44 pt target.

## VoiceOver and keyboard

- The bar is two elements: a button labelled "<title>", value "Pinned card", hint "Shows the card", and a button "Unpin".
- The sheet's title is the card title; Close and Unpin are labelled. The card inside reads as in the transcript.
- The card's context menu (Pin Card / Unpin Card) is also an accessibility action on the card.
- Mac: the bar's button is reachable by Tab with keyboard navigation on; Space opens the popover, Escape closes it.

## Context menu on the card

The surface gets its own `.contextMenu` with Pin Card or Unpin Card, outside the `.disabled` that greys the card while a turn runs (so it works mid-turn). The reply's message menu (Copy, Select, Share) still wraps the prose; a long press or right-click on the card itself shows only Pin/Unpin (the inner menu wins), which is fine since copying a card's raw JSON was never useful. Carousel tiles keep their own Open, Copy Link and Share menu.

## Tests

- Unit (`CrewTests`, `ChatPinsTests`, temporary file): a new card pins; a newer card replaces it; unpin survives a reload of the file with the same newest card fed again; an older card arriving after an unpin (history newest page first) does not pin; no card is a no-op; the same card with a later device time does not re-pin; the same surface id with a new block pins again; a card older than `since` does not pin; pinning an older card by hand; a bot's pins cleared alone; Sign Out reset; two chats independent. Shown failing first against a `ChatPins` stub that never pins.
- UI (`CrewUITests`, `PinnedCardUITests`, private simulator, fixture `chat-a2ui-pinned`): the bar shows the newest card's title, tapping it opens the sheet and it stays open for 3 s, swiping it down keeps the bar, the X removes it, long-press Pin Card on a card brings the bar back with that card's title. Fails on `main`: there is no bar.
- Renders: `chat-a2ui-pinned` (bar over the composer with the card in the transcript above) on iOS and Mac, light and dark, plus the sheet captured by the UI test. Mac renders come out blank while the Mac is locked; the PR says so if they are.
- Mac offscreen probe with the pinned fixture at `width:0` and with the inspector open: `PROBE survived`.
- Real server on `crew-test`: ask for a recipe card, see it pin, ask two follow-ups (it stays), ask it to change the recipe re-using the surface (bar title follows), relaunch (still pinned), X (gone), relaunch (still gone), ask for another card (pins).
- PLAN.md gets one Decisions line (bar, rule, `pins.json`); no locked UI value changes.
