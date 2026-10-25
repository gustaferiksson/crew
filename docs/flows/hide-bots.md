# Hide bots (#109, #114)

Hide a bot from the bot list without deleting it. The flag is Hermes' own `ui_meta["hermes-bots"].hidden`, the same one Hermes Desktop's Hide Bot and eye toggle use, so a hide on iPhone shows on the Mac, in Desktop and in Hermex. Rooms have no Hermes-side hidden flag, so only bots can be hidden.

## Model: Photos' Hidden album

Messages has no hide (its "Hide Alerts" is a mute) and Mail's Archive is a mailbox. The closest standard is the Photos Hidden album: an item leaves the main views, lives in one collapsible place, and only Unhide brings it back. So:

- A hidden bot stays hidden when it replies, works or waits for approval. New activity never unhides it.
- It is a UI hide only: no mute. Server pushes are unchanged. The local fallback notifications already skip hidden bots (existing behaviour, kept).
- Tapping a push for a hidden bot opens its chat; the bot stays hidden.
- No app icon badge: Crew sets none today and pushes carry no `badge`. If one is added, hidden bots don't count toward it.

## Surfaces

- **Bot list (iPhone and Mac, regular width):** Hide in the row's context menu and trailing swipe (`eye.slash`); in the Hidden section the same places say Unhide (`eye`). Disabled while offline. Hidden bots leave favourites and sections; a pinned bot keeps its pin and section and goes back to them on Unhide.
- **Hidden section:** last in the list, only when at least one bot is hidden. The header reads "Hidden", the count and a chevron, collapsed by default; tapping it expands with the system animation. While collapsed and any hidden bot is unread, the header shows the rows' blue unread dot before the count (Mail's unread mark on a mailbox); expanded, the rows carry their own dots. Only unread counts: working, waiting and failed hidden bots don't light the header (waiting still pushes). Rows are the normal bot rows (status, unread dot, preview, time), ordered like every section (waiting > working > unread > newest).
- **Open chat:** hiding the bot whose chat is open deselects it (empty detail on the Mac, back to the list on iPhone). A hide from another device leaves an open chat open until the user moves on.
- **Mac sidebar strip:** no hidden tiles; widen the sidebar to reach the Hidden section.
- **Search:** typed names and message search include hidden bots (Hermex shows hidden bots that match a search). Results are not marked hidden.
- **New Group:** the member picker keeps leaving hidden bots out.
- **Light/dark:** system header and row colours, see renders.

## States

- Empty: no hidden bots, no section. All bots hidden: the list shows only the Hidden section.
- Error: a failed write shows the list's "Something Went Wrong" alert; a revision conflict reloads and retries like Pin.
- Offline: Hide/Unhide disabled; the section still shows from cache.
- Long content: rows truncate like every bot row; the header count is a number.

## Verification

- Unit: `HiddenBotsTests` (favourites/sections/Hidden split, pinned + hidden), `hiddenSectionIsUnreadOnlyWhileAHiddenBotIsUnread` (header dot aggregation), `MessageSearchTests.hiddenBotsAreStillSearched` (fails on main).
- Real server: `Tests/bot_probe` hides and unhides the throwaway `crew-test-tmp` and checks the flag round-trips.
- Renders: `sidebar-flat` (collapsed, hidden bot unread: header dot) and `sidebar-hidden` (expanded), iOS and Mac, light and dark.
- Renders: `docs/flows/renders/hide-bots-*.png`.
