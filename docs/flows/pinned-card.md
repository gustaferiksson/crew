# Pinned card: the bot's latest A2UI card stays one tap away in the navigation bar

A bot's card (a recipe, a route, a comparison) scrolls away as soon as the user asks a follow-up, and they scroll back up to find it (user request 2026-11-01: "pinned until I dismiss it, like a sheet, or a better suggestion"). The newest card pins itself as a button with the card's symbol in the chat's navigation bar, next to Chat Options. Tapping it shows the whole, live card (a sheet on iPhone, a popover on iPad and Mac); Unpin lives in that sheet, in the button's long-press menu and in the card's context menu. The card also stays where it was in the transcript, as its compact preview.

## Why not a bar above the composer (redesign, user feedback on v0.1.49)

The first version was a full-width glass capsule directly above the composer. The user: "there is something with that pinned row I don't like". Concretely, from the v0.1.49 screenshot and the `chat-a2ui-pinned` render:

- **Two composers.** The bar and the composer were glass capsules of the same height, the same width and the same side margins, stacked 8 pt apart, so the bottom of the screen read as two text fields. The cited precedent, Music's mini player, sits above a tab bar, a control of a different shape and content; above Messages' composer Apple stacks nothing.
- **A copy of what is on screen.** The newest card is almost always the last thing in the transcript, so its compact preview (tile, title, subtitle) sat right above a second, smaller copy of itself. Duplication was the normal state, not an edge case.
- **It cost a row of conversation** (52 pt on iPhone) in every chat with a card, all the time, for something used occasionally.
- **The X** invited an accidental unpin next to the field the thumb aims for, and is not how Apple dismisses an accessory (Music's mini player has no close button).

Alternatives rendered (PR #<n>): a content-hugging chip above the composer without the X (still a second glass shape in the composer stack and still a copy of the preview right above it; no Apple screen puts a chip there), and hiding the bar while its preview is on screen (a bar that comes and goes as you scroll; no Apple screen does that).

## Apple's precedent

A persistent reference to something tied to the current conversation or page, that opens it on tap, is a navigation bar button in Apple's apps:

- **Safari's Downloads button** (Mac, iPad): a toolbar button that appears only while there is something to show, opens a popover with it, can be cleared from inside that popover, and stays until the popover closes. This is the shape followed here: present only while a card is pinned, popover from the button, Unpin inside it. On iPhone Safari has no such button (downloads live in the page menu).
- **Notes' Collaboration button**: a trailing toolbar button for state attached to the note, a popover on iPad and Mac and a sheet on iPhone; the precedent for the same button on iPhone.
- **Messages:** during a group FaceTime call the conversation's navigation bar button turns into the live call; Messages never stacks a bar on its composer.

HIG Toolbars: the trailing zone holds "critical/persistent items"; toolbar items use "system-provided symbols without borders"; on the Mac "every toolbar item must also exist as a menu bar command". HIG Popovers: a popover is anchored to the control that shows it.

## The pin rule

- **Unit:** one A2UI surface (`surfaceId`). A block that creates several surfaces offers each; the newest is the last one created in transcript order.
- **Auto-pin:** when a new card arrives, it becomes the chat's pinned card and replaces whatever was pinned.
- **Seen watermark:** each chat stores `seen`, the newest card it has already considered: its fingerprint (surface id plus a SHA-256 of the block text, stable between live and history replies; `SurfaceStore` already keys blocks by that text) and its turn's finish time. A card is new only when its finish time is later than `seen`'s and its fingerprint differs. So a relaunch, a history window that briefly lacks the newest reply, room pages arriving newest first, or Compact never re-pin an older or the same card; a transcript with no card changes nothing; and a live card (device time) reloaded from history (server time) is still recognised by its fingerprint. A new `createSurface` reusing an old id ("recipe" again) has a new fingerprint and a later time, so it pins.
- **Old cards never auto-pin:** a chat with no entry starts from `since`, the moment Crew first created the pins file (fresh install, first launch with this feature, or after Sign Out). Opening a chat whose newest card is weeks old shows no button; a card that arrived while Crew was closed (bot answered, push tapped) is newer than the watermark and pins.
- **Clock skew:** live turns finish at device time, history turns at server time. With the device clock ahead of the server by some seconds, a newer card loaded from history within those seconds of the previous one does not auto-pin. Accepted (cards seconds apart are rare; Pin Card covers it).
- **Identical blocks:** a bot that repeats a block word for word produces the same fingerprint (and `SurfaceStore` already shows it once), so after an unpin it does not pin again. Accepted.
- **Unpin:** the button's long-press menu, the sheet's Unpin, or the card's context menu clears `pinned`. It stays unpinned until a newer card arrives or the user pins one by hand.
- **Pin by hand:** every card in the transcript has a context menu with Pin Card or Unpin Card. Pinning an older card replaces the current pin; a newer card later still replaces it.
- **Updates:** a later block that only updates an existing surface (`updateComponents`, `updateDataModel`) is not a new card. The button and the open sheet show the live surface, so a pinned card that updates shows the new symbol and content immediately and stays pinned (or unpinned).
- **Gone:** if the pinned surface is not in the current transcript (Start New Chat, Compact Chat, the server no longer returns that reply), the button is hidden; the stored pin is harmless and is replaced by the next card.

## Storage

`ChatPins`, an `@Observable` store shaped like `ChatDrafts`: `pins.json` in Application Support (`{since, chats: {chatID: {seen, pinned}}}`), written atomically on each change, never `UserDefaults` and never `drafts.json` (its decoder expects `[String: String]`, a new shape would drop everyone's drafts). Keys are the drafts' keys: `bot.id` for a Bot Chat, `room.selectionID` for a room. Per device, not synced (like drafts). Cleared for a bot when it is deleted here; reset on Sign Out at both call sites that reset drafts (`SettingsView`, `BotsView`), and Settings' Sign Out text gains "pinned cards". Snapshots and UI tests use an in-memory fixture store and `ChatPinsTests` a temporary file, so neither writes the real file (Application Support is shared by Debug and release Mac builds, like `drafts.json`).

The logic (newest card in, pinned card out) lives in `ChatPins` so `CrewTests` can test it without the A2UI package. `SurfaceStore.sync`, on the existing turn-status sync, walks `transcript.turns` from the end to find the newest rendered card (surface id, block text, turn finish time; not the last ingested block, since older pages can arrive later), using a cached reply-to-blocks map so no markdown is parsed again, and hands it to `ChatPins`. Nothing new runs per streamed token. Two views of one chat (main window and a Mac chat window) feed the same card; the watermark makes that idempotent, and each view has its own open/closed sheet state.

## The button

- **Where:** a `ToolbarItem(placement: .primaryAction)` of `ChatView`, so it sits in the chat's navigation bar (iPhone, iPad) or window toolbar (Mac), at the trailing end after Chat Options (Bot Chat) or Threads (rooms), sharing their glass group on iOS. The two come from different `.toolbar` modifiers (`ChatScreen` and `ChatView`); SwiftUI places the inner view's item last, which the renders confirm. Present while a card is pinned and in the transcript, and also while the card it opened is still showing after an Unpin (like Safari's Downloads button, so the open popover keeps its anchor); no space is reserved otherwise. Nothing is added to the bottom bar stack: the composer stands alone again, the transcript keeps its full height, and the transcript inset, Jump to Latest offset and window minimum (#60) are the composer's alone, as before pinning existed.
- **Look:** the card's own SF Symbol (the Header `symbol` through `systemSymbol`, else `rectangle.on.rectangle`) as a standard toolbar button: monochrome, on the bar's system glass, no tile and no tone colour (HIG: monochromatic toolbar items, no tinted controls). The symbol is what tells it apart from Chat Options; the title shows in the sheet and in VoiceOver, and on the Mac as the button's help tag. A card whose symbol happens to match a neighbour (`ellipsis`) is accepted: bots pick content symbols (fork and knife, bag, map).
- **Long press (iPhone, iPad) or a click-and-hold (Mac):** a menu with Unpin (`pin.slash`). It is `Menu(primaryAction:)`, the system's bar-button pattern for "tap does the main thing, hold shows more" (Safari's Back button), with the menu indicator hidden.
- **Visible while a request card shows:** the button no longer stacks with payment, approval, question or shop cards, so the old "hidden while a request card shows" rule goes. A request arriving still closes an open card sheet or popover (`docs/flows/compact-cards.md`), so the request gets the attention.
- **Appearance:** toolbar items come and go with the system's own toolbar animation.

## The Mac menu bar

View > Show Pinned Card / Hide Pinned Card, after Show/Hide Inspector, no shortcut, disabled when the front window's chat has no pinned card (the-menu-bar: disable, don't hide). It toggles the same popover on the toolbar button through a focused scene `Binding<Bool>`, like the Inspector command. Unpin has no menu bar command: it is an action on the card (inside its popover and in its context menu), not a toolbar item.

## Opening the card

- **One open card per chat:** tapping the button presents the card with `.popover` attached to the toolbar button and `.presentationCompactAdaptation(.sheet)`: a popover from the button on Mac and iPad (a sheet in compact-width iPad windows), a sheet on iPhone. The toolbar item is not a list row, so it is a stable anchor (PLAN's presentation rule), and it stays while its card is open. Transcript previews keep their own popover, owned by `ChatView` and anchored at the preview (`docs/flows/compact-cards.md`); `openedCard` with no anchor means "opened from the pinned button". Both use the same content and the same `openedCard` state, so at most one is open. The host is chosen only when nothing is open: a tap on a preview or the button while a card is open changes only `openedCard.id` and keeps the presentation, so the iPhone sheet at medium swaps its card in place instead of dismissing one presentation and presenting another.
- **iPhone sheet:** opening dismisses the keyboard first. `.presentationDetents([.medium, .large])` starting at medium, `.presentationBackgroundInteraction(.enabled(upThrough: .medium))`: at medium the user can still scroll and read the transcript above it. Content: the live surface on the sheet's own background, in a scroll view, with the card's title as the inline navigation title, close (`Button(role: .close)`) leading and Unpin (`pin.slash`) trailing. Unchanged from v0.1.49.
- **Mac and iPad popover:** 440 pt wide, at most 560 pt tall with the card scrolling inside, arrow pointing at the toolbar button; clicking elsewhere (into the composer) or Escape closes it and keeps the pin. On the Mac Unpin sits in a small row at its top and there is no close button. Unchanged from v0.1.49 apart from the anchor.
- **The card in the sheet or popover** behaves exactly like before: its buttons send the same action to the bot, it is disabled while a turn runs, and the sheet stays open after a button tap while the reply streams behind it.
- **Dismissing vs unpinning:** swiping the sheet down, close, Escape or clicking outside only closes it; the button stays. Unpin in the sheet, the button's long-press menu, or the card's context menu unpins; the sheet stays open after Unpin, showing Pin (as for any card, `docs/flows/compact-cards.md`), and the button goes when it closes.
- **The card changes while open:** the sheet follows the surface id, so a follow-up that re-creates the same id swaps the content in place. It closes only when no surface with that id is left in the transcript. A different newer card replaces the pin and the button's symbol; the open sheet keeps the card the user opened.

## Surfaces and directions

- **Bot Chat, iPhone, iPad and Mac, light and dark:** as above. Light and dark come from the system toolbar glass and the template symbol.
- **Rooms:** same button next to Threads, keyed by the room; any member's card counts as the newest. Title fallback is "Card".
- **Other Conversations sheet (search result or Info tab):** no button and no Pin action (no stored chat key).
- **Chat windows on Mac (`BotChatWindow`):** the same `ChatView`, so the button is in that window's toolbar too; the main window and a chat window share the pin and an unpin in one shows in the other.
- **Bot list preview, time, status, unread, push, inspector:** unchanged. The pin is client-only and sends nothing to the server.
- **Sender, receiver, replies back:** the bot sends the card; the user only pins, unpins and taps through. A button tapped in the sheet sends the same hidden action row as in the transcript.
- **Haptics:** a light impact for Pin and Unpin by hand; nothing for an auto-pin, a newer card replacing the pin, or opening the sheet.

## States

- **No title:** first Text line, else "Card from <bot>" ("Card" in a room), used for the sheet title, VoiceOver and the Mac help tag; no symbol falls back to `rectangle.on.rectangle`.
- **Long title:** the button shows only the symbol; the sheet's inline title truncates; VoiceOver reads it whole.
- **Card updates while pinned:** the button's symbol and label and the open sheet follow the live surface; pin state unchanged.
- **Card whose turn failed or was stopped:** as before, only a rendered card may pin.
- **Streaming:** nothing happens until the reply finishes.
- **Busy:** the card is disabled in the sheet like in the transcript; the button stays tappable.
- **Offline:** the button and sheet still open (the card is local), while Chat Options next to it is disabled; intended, as the transcript previews stay tappable offline too.
- **Empty chat, no cards, Rich UI off:** no button.
- **Keyboard up (iOS):** the button stays in the navigation bar; tapping it closes the keyboard and opens the sheet.
- **Narrow bars:** on iPad and Mac the system moves toolbar items it cannot fit into its own overflow menu, and the button carries `visibilityPriority(.high)` so it outlasts Chat Options; covered by the Mac offscreen probe at the window minimum and with the inspector open. On iPhone trailing items do not overflow: the principal persona pill gets the remaining width and truncates the bot's name first (its existing behaviour with long names). Rendered on iPhone 18 Pro only.
- **Large Dynamic Type:** a toolbar symbol; the system's Large Content Viewer shows its title on a long press with accessibility sizes.

## VoiceOver and keyboard

- The button is one element: label "<title>", hint "Shows the card", and an explicit "Unpin" accessibility action (a toolbar `Menu` does not reliably expose its items as actions or pass an accessibility value through).
- The sheet's title is the card title; Close and Unpin are labelled. The card inside reads as in the transcript.
- The card's context menu (Pin Card / Unpin Card) is also an accessibility action on the card preview.
- Mac: View > Show Pinned Card from the keyboard; Escape closes the popover. With full keyboard navigation on, the toolbar button is reachable as any toolbar item.

## Context menu on the card

The surface gets its own `.contextMenu` with Pin Card or Unpin Card, outside the `.disabled` that greys the card while a turn runs (so it works mid-turn). The reply's message menu (Copy, Select, Share) still wraps the prose; a long press or right-click on the card itself shows only Pin/Unpin (the inner menu wins), which is fine since copying a card's raw JSON was never useful. Carousel tiles keep their own Open, Copy Link and Share menu. Where there is no pin (Other Conversations) the card's menu is empty; whether SwiftUI then falls through to the reply's message menu on a long press on the card is unverified, and losing Copy of a card's raw JSON there is accepted.

## Tests

- Unit (`CrewTests`, `ChatPinsTests`): unchanged; the pin rule did not change.
- UI (`CrewUITests`, `PinnedCardUITests`, private simulator, fixture `chat-a2ui-pinned`): the navigation bar button labelled with the newest card's title opens the sheet and it stays open 3 s; swiping it down keeps the button; Unpin in the sheet keeps the sheet open and the button goes once it closes; the transcript preview opens the same sheet; Pin in it brings the button back; the button's long-press menu Unpin removes it; long-press Pin Card on a preview brings it back; with the button's sheet open, tapping another preview swaps the sheet to that card. Fails on `main`: there the pinned element is a bar above the composer, not in the navigation bar.
- Renders: `chat-a2ui-pinned` on iOS and Mac, light and dark (the fixture gains the Chat Options menu so the bar looks like the real chat), plus the before render and the alternative chip render in the PR.
- Mac offscreen probe with the pinned fixture at `width:0` and with the inspector open: `PROBE survived`.
- Real server: not needed, no server traffic or pin rule changed.
- PLAN.md: the "Pinned card" Decisions line is rewritten (navigation bar button, Safari Downloads precedent, no bar above the composer), and the "Compact cards" and "Transcript edge effects" lines lose their mentions of the bar; no locked UI value changes.
