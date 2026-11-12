# Pinned card: the bot's latest A2UI card stays one tap away in a chip above the composer

A bot's card (a recipe, a route, a comparison) scrolls away as soon as the user asks a follow-up, and they scroll back up to find it (user request 2026-11-01: "pinned until I dismiss it, like a sheet, or a better suggestion"). The newest card pins itself as a small chip just above the composer's `+` button: the card's coloured symbol tile and its title in a content-width glass capsule. Tapping it shows the whole, live card (a sheet on iPhone and on the Mac, a popover on iPad); Unpin is the chip's small trailing X, its context menu, that sheet and the card's context menu (on the Mac the chip's X, its context menu, the sheet and the card row's context menu). The card also stays where it was in the transcript, as its compact preview.

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

View > Show Pinned Card, after Show/Hide Inspector, no shortcut, disabled when the front window's chat has no pinned card (none, or hidden behind a request card). It does what clicking the chip does (below) through the focused value `showsPinnedCard` (`Binding<Bool>?`), the same binding the chip sets. It was Go to Pinned Card while the Mac jumped to the card in the transcript (v0.1.65); with the card in a sheet it shows something again, and the sheet's own Done and Escape close it, so the item is one-way "Show", not a Show/Hide toggle.

## Opening the card

- **One open card per chat:** tapping the chip sets `openedCard` with the card id and no anchor, and `ChatView` presents the one card popover (`.presentationCompactAdaptation(.sheet)`) anchored at the chip's current frame (so on iPad the arrow follows the chip down when opening dismisses the keyboard), as for a transcript preview: a popover from the chip on iPad (a sheet in compact-width iPad windows), a sheet on iPhone. On the Mac the chip opens the same `openedCard` in a sheet (below); transcript previews on the Mac expand inline instead. While a card is open, a tap on the chip or a preview changes only the card id and keeps the current anchor, so the iPhone sheet at medium swaps its card in place.
- **iPhone sheet:** opening dismisses the keyboard first. `.presentationDetents([.medium, .large])` starting at medium, `.presentationBackgroundInteraction(.enabled(upThrough: .medium))`. Content: the live surface on the sheet's own background, in a scroll view, with the card's title as the inline navigation title, close leading and Unpin trailing. Unchanged.
- **iPad popover:** 440 pt wide, at most 560 pt tall with the card scrolling inside, arrow pointing at the chip; tapping elsewhere or Escape closes it and keeps the pin. Unchanged.
- **Mac sheet** (user feedback 2026-11-12 on v0.1.65: "clicking the pinned one just jumps up and expands, not a nice UX, Im thinking we could do some dialog or something", and the iPhone sheet is "flawless"): clicking the chip, or View > Show Pinned Card, sets `openedCard` and `ChatView` presents `.sheet` on the chat's window with the same `PinnedCardContent` as iPhone. Presented from `ChatView` (the screen container), not the chip, so it survives Unpin removing the chip.
  - **Layout:** the live card in a vertical scroll view with 20 pt margins, Unpin (or Pin after unpinning) at the bottom leading edge (`.destructiveAction`; `.secondaryAction` did not show in the sheet's bar) and Done at the bottom trailing edge (`.cancellationAction`, so Escape closes it, checked by `PinnedCardSheetTests`; as `.confirmationAction` Escape did nothing). No navigation title: Mac sheets have no title bar, and the card's own header names it.
  - **Size:** 440 pt wide, or the card's widest table plus its margins (the `TableWidth` preference), up to 800 pt; as tall as the card, up to 640 pt, then the card scrolls.
  - **Why a sheet, not a popover:** the user rejected the Mac card popover on 2026-11-11 ("I dont like the popover", `docs/flows/compact-cards.md` > The Mac), and a popover from a 30 pt chip at the window's bottom edge has little room for a table. A sheet is what iPhone already does for the same chip, it is modal to the one chat window like Mail's and Messages' detail sheets, and it leaves the transcript where the reader was (the jump lost their place).
  - **Focus:** the sheet takes keyboard focus and the composer is unavailable while it is open (a sheet is window-modal); closing it returns focus to the window. Accepted: the Mac card popover was rejected and the jump lost the reader's place; a follow-up is one Escape away, and the iPhone sheet the user called flawless has the same trade-off at large.
  - **Replies back:** a button pressed in the card sends the hidden action as from the transcript; the sheet stays open and follows the surface, and the reply lands at the end of the transcript behind it.
  - **No haptics**, as before.
- **Dismissing vs unpinning:** swiping the sheet down, close, Escape or clicking outside only closes it; the chip stays. On the Mac, Done or Escape closes the sheet and keeps the pin and the chip. Unpin on the chip's X or context menu, the sheet or the card's context menu unpins; the sheet stays open after Unpin, showing Pin, and the chip goes. The popover is presented by `ChatView`, not the chip, so it survives the chip leaving.
- **The card changes while open:** the sheet follows the surface id; it closes only when no surface with that id is left. A different newer card replaces the pin and the chip; the open sheet keeps the card the user opened.

## Surfaces and directions

- **Bot Chat, iPhone, iPad and Mac, light and dark:** as above. Light and dark come from the glass and semantic colours; the tile keeps white on the tone gradient in both.
- **Rooms:** same chip, keyed by the room; title fallback "Card".
- **Other Conversations sheet:** no chip and no Pin action.
- **Chat windows on Mac (`BotChatWindow`):** the same `ChatView`, so the chip shows there too; the pin is shared between windows, and the chip and View > Show Pinned Card (front window) open the sheet on that window only.
- **Bot list preview, time, status, unread, push, inspector:** unchanged; the pin is client-only.
- **Sender, receiver, replies back:** unchanged; a button tapped in the sheet sends the same hidden action row as in the transcript.
- **Haptics:** a light impact for Pin and Unpin by hand; nothing for an auto-pin or opening the sheet.

## States

- **No title:** first Text line, else "Card from <bot>" ("Card" in a room); no symbol falls back to `rectangle.on.rectangle`.
- **Long title:** one line, tail truncation at the composer's trailing margin; VoiceOver reads it whole.
- **Card updates while pinned:** the chip's tile and title and the open sheet (the expanded card on the Mac) follow the live surface.
- **Failed or unfinished card, streaming:** never pins (unchanged).
- **Busy:** the chip stays tappable; the card is disabled in the sheet (inline on the Mac) while a turn runs.
- **Offline:** the chip and sheet still open (the card is local).
- **Empty chat, no cards, Rich UI off:** no chip.
- **Keyboard up (iOS, iPadOS):** the chip rides up with the composer and moves to the 16 pt margin with it; tapping it closes the keyboard and opens the sheet, or on iPad the popover, which follows the chip as it moves down.
- **Large Dynamic Type:** the chip grows with the text (one line), the tile scales.

## VoiceOver and keyboard

- The chip is two buttons: the chip itself (label "<title>", value "Pinned card", hint "Shows the card", and an "Unpin" action) and its X, labelled "Unpin".
- The sheet's title is the card title; Close and Unpin are labelled.
- Mac: View > Show Pinned Card from the menu bar (keyboard menu navigation); the chip is focusable with full keyboard navigation and Space opens the sheet; Escape closes it.

## Context menu on the card

The surface gets its own `.contextMenu` with Pin Card or Unpin Card, outside the `.disabled` that greys the card while a turn runs (so it works mid-turn). The reply's message menu (Copy, Select, Share) still wraps the prose; a long press or right-click on the card itself shows only Pin/Unpin (the inner menu wins), which is fine since copying a card's raw JSON was never useful. Carousel tiles keep their own Open, Copy Link and Share menu. Where there is no pin (Other Conversations) the card's menu is empty; whether SwiftUI then falls through to the reply's message menu on a long press on the card is unverified, and losing Copy of a card's raw JSON there is accepted.

## Tests

- Unit (`ChatPinsTests`): unchanged; the pin rule did not change.
- UI (`PinnedCardUITests`, private simulator, fixture `chat-a2ui-pinned`): the chip (label the card's title, value "Pinned card") sits above the composer with its Unpin X inside it, not in the navigation bar, and its tap opens the sheet, which stays open 3 s; swiping down keeps the chip; Unpin in the sheet keeps the sheet open and the chip goes; the preview opens the same sheet and Pin brings the chip back; the chip's X removes it and Pin Card on a preview brings it back; the chip's context menu Unpin removes it and Pin Card brings it back again; with the chip's sheet open, tapping another preview swaps the card. Fails on `main`: the pin is a navigation bar button there.
- Renders: `chat-a2ui-pinned` on iOS and Mac, light and dark.
- Mac offscreen probe with the pinned fixture at `width:0`: `PROBE survived`.
- PLAN.md: the "Pinned card" Decisions line is rewritten for the chip.
- Mac (2026-11-12): `PinnedCardSheetTests`, an offscreen host test of `ChatView` driven through the same focused value as View > Show Pinned Card: it opens a sheet on the window wider than 560 pt with the table not scrolling, and Escape closes it (fails with Done as `.confirmationAction`). Renders `chat-a2ui-pinned-sheet` on the Mac, light and dark. It replaces `PinnedCardJumpTests` of the jump (v0.1.65).
