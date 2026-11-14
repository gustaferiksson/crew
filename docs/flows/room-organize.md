# Room pinning and sections (#116)

Pin a room as a favourite tile and file it in a section, with the same menu items, swipe and tiles a bot has. Pictures and manual ordering are not in this slice (see "Not in this slice").

## Where the data lives

Hermes v0.23.1 keeps nothing on the server for a gateway room's pin, section, order or picture: `hosted_rooms` has only id, name, members and bookkeeping columns, and profile assets accept only `avatar`. Desktop treats gateway rooms the same way: `roster-pane-derivation.ts` gives every gateway row `pinned: false`, `groupRowsBySection` and `group-order.ts` skip gateway rows, and `CanonicalGroupRow` draws a generic icon with only Open and Disband. Desktop's pin, section and order exist only for its own Desktop-driven rooms, and even there they live in Desktop's plugin storage, never on the server (`types.ts` `GroupChat.pinned`, `sectionId`, `rosterOrder`: "local ... deliberately absent from the bounded gateway sync projection").

So Crew keeps room pins and sections per device, like Desktop: `room-layout.json` in Application Support (`RoomLayout`, the `ChatPins`/`ChatDrafts` pattern, never `UserDefaults`), keyed by `room_id`, holding `pinned` and the section's id and name. A pin on the iPhone does not show on the Mac or in Desktop. Crew never writes Desktop's `hermes-bots-groups` mirror: Desktop would adopt such an entry as a Desktop-driven room (a duplicate row).

## Surfaces

- **Bot list rows (iPhone and Mac, regular width):** a room row gets the bot row's leading swipe (Pin/Unpin, orange) and a context menu with Pin/Unpin and Move to Section (the section list, New Section…, Remove from Section when filed), from the same builders as the bot menu. On the Mac the menu comes from the list's `contextMenu(forSelectionType:)`, which today resolves only bot ids. No Hide (rooms have none), no Duplicate, no Open in New Window (rooms stay out of chat windows). The room items stay enabled offline: the write is local (Messages pins offline too).
- **Favourites:** pinned rooms follow pinned bots in the favourites grid as tiles: `GroupAvatar` at the tile size, the room name, and a second line with "Draft" in red when the room has an unsent draft (also its accessibility value), else "N members". Pinned rooms sort newest `updated_at` first. The grid shows when either list is non-empty. A tap selects the room; the tile's context menu is the room menu. No double-click or Open in New Window on the Mac: rooms stay out of chat windows.
- **Sections:** a filed room sits in its section, placed among the section's bots by the existing rule for the Other block (before the first idle bot it is newer than). A section exists while anything is in it: a room-only section (made with New Section… from a room) shows with its name, sorted A to Z among the bot sections; its rooms sort newest first. Unpinning a filed room returns it to its section. A bot section's current name wins over the name the room stored (a rename from Desktop shows). Unfiled rooms stay in Other; Other gets its header only when named sections exist.
- **Move to Section lists:** both menus list the union of bot sections and room sections, so a bot can join a room-only section and the other way round.
- **Mac sidebar strip:** favourite bots, then pinned rooms, then each section's rows in order, then unfiled rooms; no headers.
- **Active Now filter and search:** unchanged: every room still shows when it matches, pinned or filed.
- **Room header, inspector, push, bot-list previews, New Room:** unchanged (no picture in this slice; rooms have no push).
- **Light/dark:** system tile and row colours; renders in both.

## States

- **Empty:** no pinned bots or rooms, no grid. All rooms pinned, no bots in Other: no Other section.
- **A deleted section:** Crew deletes a section by emptying it. When its last bot leaves (here or on another client) a room filed there keeps the section alive as a room-only section; Remove from Section returns the room to Other.
- **A room pinned on another client:** cannot happen across clients (per device); a room pinned on this device's other install (iPhone vs Mac) is not shown pinned. Said in the PR.
- **Disbanded room:** its saved layout entry is cleared on disband from this device; an entry for a room missing from `groups.list` is ignored, never pruned (the list empties on reconnect and unsupported servers, and it pages at the server's limit). Stale entries are a few bytes each.
- **Sign out:** clears the file, like drafts and card pins.
- **Error:** the write is a local file save; a failed write keeps the in-memory state for the session.
- **Offline:** room items work (local write); bot items stay disabled; the layout applies from the file.
- **Long content:** tile names truncate to one line like bot tiles; room rows unchanged.

## Not in this slice

- **Room picture:** no server home on v0.23.1 for a gateway room (see above), and Desktop shows none for them. Needs a decision: per-device file, or a new Crew-only ui_meta key on the default profile (rides every 2 s `profiles.list`).
- **Move Up / Move Down:** Desktop offers ordering only for its Desktop-driven rooms, per Desktop. Crew orders rooms by activity like bots.

## Verification

- Unit: `RoomLayoutTests`: persistence round trip, pinned rooms leave sections, filed rooms land in their section, a room-only section appears and sorts by name, a bot section's name wins, Remove from Section returns to Other, section tag union, reset clears.
- Real server: nothing to round-trip (no server field); `groups.list` on v0.23.1 returns no layout keys (`Tests/fixtures/rooms/list.json`).
- Renders: `sidebar-rooms` (Launch Crew pinned, Docs Review filed under Work), iOS and Mac, light and dark. Mac layout probe for the strip and inspector.
- iOS UI tests: the bot list classes via `Tests/ui.sh`.
