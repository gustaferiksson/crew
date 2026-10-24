# Sidebar strip on the Mac (replaces #143's compact rows)

Dragged narrow, the Mac sidebar turns into one column of avatar tiles with the name under each, like macOS 27 Messages. #143's compact rows (avatar and name on one line) are removed on both platforms; this replaces `docs/flows/compact-sidebar.md`.

## What Apple does (measured)

From a 2x screenshot of macOS 27 Messages with its sidebar dragged narrow:

- Column 94 pt wide. One column of tiles, 78 x 86 pt, 8 pt in from each side, no gap between tiles (86 pt from one avatar to the next).
- Avatar 40 pt (the regular row size, not larger), 15 pt below the tile top, centred. Name under it, about 11 to 12 pt regular, one line, centred, truncated at the tail ("DHL Sveri…"), secondary grey; white on the selected tile.
- Selection: an accent-filled rounded tile (about 20 pt corners), the sidebar list's own selection.
- No search field, no sidebar toolbar buttons, no separators, no section headers; pinned conversations are just the first tiles. Compose stays at the leading edge of the chat's toolbar.
- Between full width and the strip Messages snaps: below a threshold the column jumps to the strip, it never shows squeezed rows.

## Platform limit: 140 pt, not 94

SwiftUI's `NavigationSplitView` on macOS 27 floors the sidebar's minimum at 140 pt whatever `navigationSplitViewColumnWidth` asks for (min 94, min 60 and the fixed `navigationSplitViewColumnWidth(94)` all give `minimumThickness` 140; a bare AppKit `NSSplitViewItem` takes 94, so the floor is SwiftUI's). Messages is not built on `NavigationSplitView`. Crew keeps the documented API and no AppKit workaround, so its strip is 140 pt wide at its narrowest, and tiles are wider than Messages' 78 pt. SwiftUI has no snapping API either, so between 140 pt and the threshold the strip fills whatever width the user leaves it. If a later SwiftUI lowers the floor, `stripWidth` (94) already asks for Messages' width.

## Rule (macOS)

- The sidebar column is `min stripWidth (94, effectively 140), ideal 320, max 400`. Window minimum: 140 + 320 = 460 pt (was 560).
- One decision for the whole list, as #143: `BotsView` reads the `List`'s outer frame with `.onGeometryChange(for: Bool.self) { $0.size.width < stripThreshold }` into `@State isStrip`. It changes only when the width crosses the threshold, so a live resize switches once per crossing, without animation.
- Threshold `stripThreshold` 260 pt, #143's derivation kept: a regular row needs a readable name ("Ada Lovelace", headline, 85 pt) beside the widest status label ("Needs approval", 82 pt) plus spacing, which is about 255 to 265 pt of column. Below that a regular row breaks, so the strip takes over. 320 (the default) is always regular.
- In the strip the `List` shows, in order: favourites, then each section's bots and groups in their usual order, then unfiled groups. No section headers, no separators, no favourites grid. Every tile is a tagged `List` row, favourites included, so selection, keyboard and menus come from the `List`.
- The search field is not attached in the strip (`.searchable` sits only on the regular branch). A query typed before narrowing is kept and comes back when the sidebar widens; the strip itself ignores it and shows every bot.
- The system sidebar toggle is removed in the strip (`.toolbar(removing: isStrip ? .sidebarToggle : nil)`), as Messages shows none; View > Hide Sidebar (⌃⌘S) still works. New Chat stays in the chat column's toolbar (unchanged).

## Tile

- `StripTile`: avatar (`rowAvatarSize`, 40 pt) with 15 pt above it and 6 pt to the name, name in `.subheadline` (11 pt), `.secondary`, one line, tail truncation, centred, 4 pt side padding; the tile is at least `stripTileHeight` (86 pt) tall and as wide as the row. Row insets zero, separator hidden.
- Selection: the system sidebar selection of the row (accent fill with white text when the window is key, grey when not), not a painted tile. Its corner radius and insets are the system's.
- Status on the avatar, as #143's compact badge: working green `ellipsis` (variable colour effect, honours Reduce Motion), waiting (approval, question, payment) orange `exclamationmark`, failed red `xmark`, a 13 pt circle knocked out of the avatar with a 2 pt gap. Unread: an 8 pt accent dot to the left of the avatar, vertically centred on it, where the regular row's dot sits.
- Groups: `GroupAvatar` and the room name; no status badge (rooms have none).
- Drafts: not shown in the tile (no room, Messages shows none); the composer keeps them and the regular row shows them again when widened.
- VoiceOver: one element per tile (`children: .ignore`), label "title, role" (or the title; the room name for groups), value the status ("Working", "Needs approval", "Waiting for you", "Wants to pay", "Failed", "Unread") plus "Draft" when a draft is pending and the chat is not open. The `List` adds "selected".

## Surfaces

- **Selection, keyboard:** arrow keys move through the tiles; Return and double click open the bot in its own window (`contextMenu(forSelectionType:primaryAction:)`), now also for favourites in the strip; ⌘O works from the selected bot as today.
- **Context menus:** the `List`'s selection menu (Open in New Window, Pin/Unpin, Duplicate, Move to Section, Delete) on bot tiles, favourites included. Group tiles have no menu, as group rows today.
- **Chat, inspector, composer, push, chat windows:** untouched. The inspector still opens from the persona pill; with it open the window minimum follows the existing inspector rule (140 + 320 + 2 x inspector width).
- **Connection pill:** at the strip's width the pill can't hold its text, so it keeps only its icon (spinner or orange `wifi.exclamationmark`) in its glass circle (`ViewThatFits`), with the state text and host as its help tooltip and VoiceOver label; when unreachable the circle is the Retry button.
- **Light and dark:** system selection, system badge colours, knockout instead of painted rings; rendered in both.

## States

- **Empty, loading, error:** "No Bots", the spinner and alerts are overlays of the list, unchanged (text wraps at 140 pt).
- **Offline:** cached tiles with cached statuses, the icon-only pill at the bottom.
- **Long names:** one line, tail truncated; role never shown.
- **Many bots:** the list scrolls; switching to the strip keeps the selection (it lives in `BotsView`), the scroll position may jump since rows change height and the `List` is rebuilt without the search field.
- **Search active while narrowing:** see Rule; results return on widening.

## iPadOS and iPhone

Messages on iPad has no strip; its rows simply get narrower. iPad keeps plain regular rows at every sidebar width (min 240, ideal 320); #143's iPad compact rows go, so a narrowed iPad sidebar truncates the name before the status label, like Messages. iPhone is full width and unchanged.

## Tests

- Unit (`CrewTests/SidebarStripTests.swift`, replaces `CompactRowTests.swift`), hosting the real views with the recorded `cold-open` roster and live sessions (unread and working phases):
  - The bot tile is exactly `stripTileHeight` (86 pt) tall in a 140 pt column, its ideal width fits 140 pt, and it is the same size for the unread and the working bot and for a bot with a long role (no status, time, role or preview laid out).
  - The threshold: `stripWidth` <= 140 < `stripThreshold` < 320, and at `stripThreshold` a regular row's text column holds the bot's name beside "Needs approval" (the derivation), while just below 240 it would not.
  - VoiceOver label and value of the tile, read from the hosted view's accessibility tree if it is reachable unhosted; otherwise read in review.
  - Shown failing on `main` (the tile doesn't exist there) and with a mutation (status label laid out in the tile, wrong threshold).
- Renders (Mac, light and dark): `sidebar-compact` drags the divider 330 then to the strip (lands on 140) in a tall window with a selected waiting bot, pinned favourites, a photo avatar, working, failed, unread and a group; again with `-snapshotSidebarWidth 262` just above the threshold (regular rows). `sidebar` and `layout` checked unchanged at the default width. Saved as `docs/flows/renders/sidebar-strip-*.png`.
- `-measure YES` on `layout` logs the new window minimum (460).
