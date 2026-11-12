# Pinned card: the bot's latest A2UI card stays one tap away in a chip above the composer

A bot's card (a recipe, a route, a comparison) scrolls away as soon as the user asks a follow-up, and they scroll back up to find it (user request 2026-11-01: "pinned until I dismiss it, like a sheet, or a better suggestion"). The newest card pins itself as a small chip just above the composer's `+` button: the card's coloured symbol tile and its title in a content-width glass capsule. Tapping it shows the whole, live card (a sheet on iPhone, a popover on iPad; on the Mac it scrolls the transcript to the card and expands it in place); Unpin is the chip's small trailing X, its context menu, that sheet and the card's context menu (on the Mac the chip's X and the chip's and the card row's context menus). The card also stays where it was in the transcript, as its compact preview.

## History: why a chip

- **v0.1.49, a full-width bar above the composer:** the bar and the message field were glass capsules of the same height, width and side margins, so the bottom read as two composers; its X sat where the thumb goes. The user: "something with that pinned row I don't like".
- **v0.1.54, a navigation bar button (#253):** a monochrome toolbar symbol next to Chat Options. The user: "Pinned is way too subtle", "too subtle up there, come up with something else". A generic white symbol in a toolbar does not say "your recipe is here".
- **Now, a chip:** it keeps what worked in v0.1.49 (close to where the user types, the card's own colour and title) and drops what didn't: it is content width, not full width; 36 pt high on iOS (30 pt on the Mac) next to the 48 pt composer row, not the same height; leading-aligned over the `+` button, not spanning the field; a small X inside the chip that unpins (#264). It reads as an accessory of the composer, not a second composer. This is the content-hugging chip rendered as the alternative in #253.

## Apple's precedent

- **iOS 26 bottom accessories:** a glass capsule floating just above the bottom bar that holds a live thing and opens it on tap (Music's and Podcasts' now-playing accessory over the tab bar). The chip is that, scaled down to its content because the composer, unlike a tab bar, is the primary control.
- **Messages' reply and attachment context:** what the next message relates to sits right above the field, compact, and does not compete with the field itself.
- **A small X (#264):** the chip first had no X, like Music's accessory, with Unpin only in its context menu; #264 added a trailing `xmark` button labelled Unpin, the same action as the context menu.

## The pin rule

- **Unit:** one A2UI surface (`surfaceId`). A block that creates several surfaces offers each; the newest is the last one created in transcript order.
- **Auto-pin:** when a new card arrives, it becomes the chat's pinned card and replaces whatever was pinned.
- **Seen watermark:** each chat stores `seen`, the newest card it has already considered: its fingerprint (surface id plus a SHA-256 of the block text, stable between live and history replies; `SurfaceStore` already keys blocks by that text) and its turn's finish time. A card is new only when its finish time is later than `seen`'s and its fingerprint differs. So a relaunch, a history window that briefly lacks the newest reply, room pages arriving newest first, or Compact never re-pin an older or the same card; a transcript with no card changes nothing; and a live card (device time) reloaded from history (server time) is still recognised by its fingerprint. A new `createSurface` reusing an old id ("recipe" again) has a new fingerprint and a later time, so it pins.
- **Old cards never auto-pin:** a chat with no entry starts from `since`, the moment Crew first created the pins file (fresh install, first launch with this feature, or after Sign Out). Opening a chat whose newest card is weeks old shows no chip; a card that arrived while Crew was closed (bot answered, push tapped) is newer than the watermark and pins.
- **Clock skew:** live turns finish at device time, history turns at server time. With the device clock ahead of the server by some seconds, a newer card loaded from history within those seconds of the previous one does not auto-pin. Accepted (cards seconds apart are rare; Pin Card covers it).
- **Identical blocks:** a bot that repeats a block word for word produces the same fingerprint (and `SurfaceStore` already shows it once), so after an unpin it does not pin again. Accepted.
- **Unpin:** the chip's X or context menu, the sheet's Unpin, or the card's context menu clears `pinned`. It stays unpinned until a newer card arrives or the user pins one by hand.
- **Pin by hand:** every card in the transcript has a context menu with Pin Card or Unpin Card. Pinning an older card replaces the current pin; a newer card later still replaces it.
- **Updates:** a later block that only updates an existing surface (`updateComponents`, `updateDataModel`) is not a new card. The chip and the open sheet show the live surface, so a pinned card that updates shows the new title, symbol and content immediately and stays pinned (or unpinned).
- **Gone:** if the pinned surface is not in the current transcript (Start New Chat, Compact Chat, the server no longer returns that reply), the chip is hidden; the stored pin is harmless and is replaced by the next card.

## Storage

`ChatPins`, an `@Observable` store shaped like `ChatDrafts`: `pins.json` in Application Support (`{since, chats: {chatID: {seen, pinned}}}`), written atomically on each change, never `UserDefaults` and never `drafts.json` (its decoder expects `[String: String]`, a new shape would drop everyone's drafts). Keys are the drafts' keys: `bot.id` for a Bot Chat, `room.selectionID` for a room. Per device, not synced (like drafts). Cleared for a bot when it is deleted here; reset on Sign Out at both call sites that reset drafts (`SettingsView`, `BotsView`), and Settings' Sign Out text gains "pinned cards". Snapshots and UI tests use an in-memory fixture store and `ChatPinsTests` a temporary file, so neither writes the real file (Application Support is shared by Debug and release Mac builds, like `drafts.json`).

The logic (newest card in, pinned card out) lives in `ChatPins` so `CrewTests` can test it without the A2UI package. `SurfaceStore.sync`, on the existing turn-status sync, walks `transcript.turns` from the end to find the newest rendered card (surface id, block text, turn finish time; not the last ingested block, since older pages can arrive later), using a cached reply-to-blocks map so no markdown is parsed again, and hands it to `ChatPins`. Nothing new runs per streamed token. Two views of one chat (main window and a Mac chat window) feed the same card; the watermark makes that idempotent, and each view has its own open/closed sheet state.

## The chip

- **Where:** in the chat's bottom bar stack, directly above the composer (or the voice composer while a voice message records) and below any payment, approval, question or shop card. While one of those cards shows the chip is hidden (the stack would get tall); it comes back when the card goes. In a room it also hides while a Reply chip shows above the composer (`docs/flows/room-reply.md`), and comes back after the send or Cancel Reply. An approval or question arriving also closes any open card sheet or popover (`docs/flows/compact-cards.md`); a payment notice or shop offer only hides the chip.
- **Look:** a Liquid Glass capsule drawn behind the content (`.background { Color.clear.glassEffect(.regular.interactive(), in: .capsule) }`, PLAN's no-glass-in-glass rule): a 24 pt circle with the card's symbol in white on the tone's gradient (the preview tile, smaller and round), then the title in `.subheadline.weight(.medium)`, one line, tail truncation, 4 pt trailing padding, then the X. 36 pt high on iOS, 30 pt on the Mac, both `@ScaledMetric` (a 36 pt target like the system's small capsule buttons; the 8 pt gap to the composer keeps it clear of the `+`). On the Mac the title is also its help tag.
- **Width and alignment:** content width, leading-aligned at the composer's own leading margin (iOS 28 pt with the keyboard hidden, 16 pt while the composer is focused; Mac 16 pt), so its left edge lines up with the `+` button. A long title truncates at the composer's trailing margin.
- **Unpin button:** a trailing `xmark` (`.caption2.weight(.bold)`, secondary) in a frame as wide as the chip's height minus 4 pt and as tall as the chip, labelled "Unpin", help tag Unpin on the Mac.
- **Context menu:** Unpin (`pin.slash`). Also an "Unpin" accessibility action on the chip.
- **Unpinned:** the chip scales to half toward its leading edge and fades out (`.scale(0.5, anchor: .leading)` with `.opacity`).
- **Window minimum (#60):** one line, no `fixedSize`, so the chip never raises the Mac window's minimum height.
- **Appearance:** the chip fades in with the composer stack's existing `.smooth` animation.
- **Transcript inset and Jump to Latest:** the chip is inside the bar stack whose height already sets the transcript's bottom inset and the Jump arrow's offset, so the arrow stays 12 pt above the top of the whole stack.
- **The preview on screen too:** the newest card's preview is often visible right above the chip. Hiding the chip while its preview (or an inline-expanded copy) is on screen was considered: it needs visibility tracking of a lazy row and makes the chip come and go while scrolling, so it is not done.

## The Mac menu bar

View > Go to Pinned Card, after Show/Hide Inspector, no shortcut, disabled when the front window's chat has no pinned card (none, or hidden behind a request card). It does what clicking the chip does (below) through a focused scene action (`(() -> Void)?` instead of the old `Binding<Bool>`). It was Show / Hide Pinned Card, a toggle of the popover; with the card inline there is nothing to hide, and an expanded card scrolled out of view would read "Hide" while nothing shows, so the item is a one-way navigation named like the Mac's "Go to" items (Finder's Go > Go to Folder). Collapsing stays on the card row (click or context menu).

## Opening the card

- **One open card per chat:** tapping the chip sets `openedCard` with the card id and no anchor, and `ChatView` presents the one card popover (`.presentationCompactAdaptation(.sheet)`) anchored at the chip's current frame (so on iPad the arrow follows the chip down when opening dismisses the keyboard), as for a transcript preview: a popover from the chip on iPad (a sheet in compact-width iPad windows), a sheet on iPhone. The Mac has no card popover (below). While a card is open, a tap on the chip or a preview changes only the card id and keeps the current anchor, so the iPhone sheet at medium swaps its card in place.
- **iPhone sheet:** opening dismisses the keyboard first. `.presentationDetents([.medium, .large])` starting at medium, `.presentationBackgroundInteraction(.enabled(upThrough: .medium))`. Content: the live surface on the sheet's own background, in a scroll view, with the card's title as the inline navigation title, close leading and Unpin trailing. Unchanged.
- **iPad popover:** 440 pt wide, at most 560 pt tall with the card scrolling inside, arrow pointing at the chip; tapping elsewhere or Escape closes it and keeps the pin. Unchanged.
- **Mac, go to the card in place** (user 2026-11-11, no popover; `docs/flows/compact-cards.md` > The Mac): clicking the chip (or View > Go to Pinned Card) adds the card to `ChatView`'s expanded set and scrolls the transcript to the card's turn through the existing `ScrollPosition`: `position.scrollTo(id: turn, anchor: .top)`, the scroll a fixture's `scrollTarget` uses; not animated (an animated id scroll does not move on the Mac host, PLAN "Transcript scrolling"). Precedent: Crew's own search jump, which takes the reader to the message in the transcript the same way.
  - **Target:** the last turn whose reply contains the block that owns the surface (`SurfaceStore.owners[id]`). A re-created id ("make it vegan") draws at its newest block, so the jump goes there, not to the older turn with the "updated below" line.
  - **Where it lands:** the turn's top at the top of the transcript. Landing on the card row itself (reviewer request) does not work with `ScrollPosition`: a `.id` on the card row inside the lazy turn is not a scroll target, and `scrollTo(id:)` on it left the offset at the turn top even with the turn laid out (`PinnedCardJumpTests`, 2026-11-11); `ScrollViewReader` is ruled out by PLAN "Transcript scrolling". So when the reply's prose above the card is taller than the window, the card row lands below the fold and the reader scrolls down to it (known limitation).
  - **The end hold stays out of it:** the position then holds the turn's id, so `TranscriptScroll` no longer follows the end (no end hold, no Mac size-change anchor) and the card grows downward from where it landed, also when the pinned card is the last turn and the jump clamps at the end. Jump to Latest shows once the end is out of view and brings the reader back; a send holds the end again.
  - **Short chat** (shorter than the window): nothing scrolls; the card expands where it is.
  - **Already expanded:** stays expanded and is scrolled to (going to the card never collapses it). **Already on screen:** still scrolled so its turn is at the top (a search hit centres its turn instead; a card is read from the top down).
  - **Focus:** the composer keeps its focus (the popover took it; the inline card does not need it), so a follow-up can be typed right away; no tint, the expanding card is the feedback.
  - **Replies back:** after the jump the position holds the turn's id, so a reply to a button pressed in the card (or to a follow-up) does not pull the reader down; Jump to Latest shows and brings them to it, and a send holds the end again. A re-created card lands at its new turn already expanded.
  - **No haptics**, as before.
- **Dismissing vs unpinning:** swiping the sheet down, close, Escape or clicking outside only closes it; the chip stays. On the Mac collapsing the card (row click or its context menu) keeps the pin and the chip. Unpin on the chip's X or context menu, the sheet or the card's context menu unpins; the sheet stays open after Unpin, showing Pin, and the chip goes. The popover is presented by `ChatView`, not the chip, so it survives the chip leaving.
- **The card changes while open:** the sheet follows the surface id; it closes only when no surface with that id is left. A different newer card replaces the pin and the chip; the open sheet keeps the card the user opened.

## Surfaces and directions

- **Bot Chat, iPhone, iPad and Mac, light and dark:** as above. Light and dark come from the glass and semantic colours; the tile keeps white on the tone gradient in both.
- **Rooms:** same chip, keyed by the room; title fallback "Card".
- **Other Conversations sheet:** no chip and no Pin action.
- **Chat windows on Mac (`BotChatWindow`):** the same `ChatView`, so the chip shows there too; the pin is shared between windows, and the chip and View > Go to Pinned Card (front window) expand the card in that window's transcript only.
- **Bot list preview, time, status, unread, push, inspector:** unchanged; the pin is client-only.
- **Sender, receiver, replies back:** unchanged; a button tapped in the sheet sends the same hidden action row as in the transcript.
- **Haptics:** a light impact for Pin and Unpin by hand; nothing for an auto-pin or opening the sheet.

## States

- **No title:** first Text line, else "Card from <bot>" ("Card" in a room); no symbol falls back to `rectangle.on.rectangle`.
- **Long title:** one line, tail truncation at the composer's trailing margin; VoiceOver reads it whole.
- **Card updates while pinned:** the chip's tile and title and the open sheet (the expanded card on the Mac) follow the live surface.
- **Failed or unfinished card, streaming:** never pins (unchanged).
- **Busy:** the chip stays tappable; the card is disabled in the sheet (inline on the Mac) while a turn runs.
- **Offline:** the chip and sheet still open, and on the Mac the jump works (the card is local).
- **Empty chat, no cards, Rich UI off:** no chip.
- **Keyboard up (iOS, iPadOS):** the chip rides up with the composer and moves to the 16 pt margin with it; tapping it closes the keyboard and opens the sheet, or on iPad the popover, which follows the chip as it moves down.
- **Large Dynamic Type:** the chip grows with the text (one line), the tile scales.

## VoiceOver and keyboard

- The chip is two buttons: the chip itself (label "<title>", value "Pinned card", hint "Shows the card" (Mac: "Shows the card in the conversation"), and an "Unpin" action) and its X, labelled "Unpin".
- The sheet's title is the card title; Close and Unpin are labelled.
- Mac: View > Go to Pinned Card from the menu bar (keyboard menu navigation); the chip is focusable with full keyboard navigation and Space goes to the card; after the jump Tab reaches the card row, whose Space collapses it.

## Context menu on the card

The surface gets its own `.contextMenu` with Pin Card or Unpin Card, outside the `.disabled` that greys the card while a turn runs (so it works mid-turn). The reply's message menu (Copy, Select, Share) still wraps the prose; a long press or right-click on the card itself shows only Pin/Unpin (the inner menu wins), which is fine since copying a card's raw JSON was never useful. Carousel tiles keep their own Open, Copy Link and Share menu. Where there is no pin (Other Conversations) the card's menu is empty; whether SwiftUI then falls through to the reply's message menu on a long press on the card is unverified, and losing Copy of a card's raw JSON there is accepted.

## Tests

- Unit (`ChatPinsTests`): unchanged; the pin rule did not change.
- UI (`PinnedCardUITests`, private simulator, fixture `chat-a2ui-pinned`): the chip (label the card's title, value "Pinned card") sits above the composer with its Unpin X inside it, not in the navigation bar, and its tap opens the sheet, which stays open 3 s; swiping down keeps the chip; Unpin in the sheet keeps the sheet open and the chip goes; the preview opens the same sheet and Pin brings the chip back; the chip's X removes it and Pin Card on a preview brings it back; the chip's context menu Unpin removes it and Pin Card brings it back again; with the chip's sheet open, tapping another preview swaps the card. Fails on `main`: the pin is a navigation bar button there.
- Renders: `chat-a2ui-pinned` on iOS and Mac, light and dark.
- Mac offscreen probe with the pinned fixture at `width:0`: `PROBE survived`.
- PLAN.md: the "Pinned card" Decisions line is rewritten for the chip.
- Mac (this change): `PinnedCardJumpTests`, an offscreen host test of `ChatView` driven through the same focused value as View > Go to Pinned Card: from the end, the jump leaves the end (6 594 pt up with the card far up, 903 pt with the card as the last turn) and stays put 1 s later, so no end hold pulls it back. Renders `chat-a2ui-pinned` on the Mac, light and dark. MenuCommands: the item reads "Go to Pinned Card" (checked by the build; Mac UI tests are disabled).
