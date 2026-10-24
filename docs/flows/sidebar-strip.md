# Sidebar strip on the Mac (replaces #143's compact rows)

Dragged narrow, the Mac sidebar turns into one column of avatar tiles with the name under each, like macOS 27 Messages. #143's compact rows (avatar and name on one line) are removed on both platforms; this replaces `docs/flows/compact-sidebar.md`, which is deleted with its renders.

## What Apple does (measured)

From a 2x screenshot of macOS 27 Messages with its sidebar dragged narrow:

- Column 94 pt wide. One column of tiles, 78 x 86 pt (a little taller than wide), 8 pt in from each side, no gap between tiles (86 pt from one avatar to the next).
- Avatar 40 pt (the regular row size, not larger), 15 pt below the tile top, centred. Name under it, about 11 to 12 pt regular, one line, centred, truncated at the tail ("DHL Sveri…"), secondary grey; white on the selected tile.
- Selection: an accent-filled rounded tile (about 20 pt corners), the sidebar list's own selection.
- No search field, no sidebar toolbar buttons, no separators, no section headers; pinned conversations are just the first tiles. Compose stays at the leading edge of the chat's toolbar.
- Between full width and the strip Messages snaps: below a threshold the column jumps to the strip, it never shows squeezed rows.

## Platform limit: 140 pt, not 94

SwiftUI's `NavigationSplitView` on macOS 27 floors the sidebar's minimum at 140 pt whatever `navigationSplitViewColumnWidth` asks for (min 94, min 60 and the fixed `navigationSplitViewColumnWidth(94)` all give `minimumThickness` 140; a bare AppKit `NSSplitViewItem` takes 94, so the floor is SwiftUI's). Messages is not built on `NavigationSplitView`. Crew keeps the documented API and no AppKit workaround, so its narrowest sidebar is 140 pt. The tiles keep Messages' size anyway: in the strip the `List` is framed to `stripWidth` (98 pt) and centred in the column, so the system selection (inset 10 pt from the list's edges) is exactly a 78 x 86 pt tile, from 140 pt up to the threshold. SwiftUI has no snapping API and no hysteresis, so the column keeps whatever width the user drags it to and the layout flips each time the width crosses the threshold (once per crossing, never per pixel).

## Rule (macOS)

- The sidebar column is `min stripWidth (98, effectively 140), ideal 320, max 400`. Window minimum: 140 + 320 = 460 pt (was 560), measured with `-measure YES`; with the inspector open 140 + 320 + 2 x its width (1140 at 340).
- One decision for the whole list, as #143: `BotsView` reads the sidebar column's frame (outside the strip's narrower `List`) with `.onGeometryChange(for: Bool.self) { $0.size.width < stripThreshold }` into `@State isStrip`.
- Threshold `stripThreshold` 280 pt, #143's derivation measured again: a regular row needs a readable name ("Ada Lovelace", headline, 85 pt) beside the widest status label ("Needs approval", 82 pt) and 4 pt spacing, 171 pt; a sidebar `List` row leaves the column width minus 106 pt for that text (16 pt list insets each side, 12 pt trailing row inset, 10 pt dot gutter, 40 pt avatar, 12 pt spacing), so a regular row stops working at about 277 pt. #143's 260 truncated that name beside "Needs approval" (it measured 154 pt). 320 (the default) is always regular.
- In the strip the `List` shows, in order: favourites, then each section's bots and groups in their usual order (`rows(in:)`, groups interleaved by recency in the unfiled section), then unfiled groups when there is no unfiled section. No section headers, no separators, no favourites grid. Every tile is a tagged `List` row, favourites included, so selection, keyboard and menus come from the `List`.
- The search field is not attached in the strip (`.searchable` sits only on the regular branch). So the `List` is rebuilt at each crossing: the selection is kept (it lives in `BotsView`), keyboard focus and the scroll offset are not (the list starts at the top, as a freshly opened list). The connection pill's 2 s timer and the message search task sit on the column, outside the rebuilt list, so a crossing doesn't reset the pill's delay. The search does not run in the strip (nothing shows its results); a query typed before narrowing is kept and searched again when the sidebar widens; the strip ignores it, shows every bot and never shows the search empty state.
- Scroll indicators are hidden in the strip (`.scrollIndicators(.never)`): a legacy (always shown) scroller would take 16 pt of the 98 pt list and clip the tiles. The strip still scrolls with the wheel, trackpad and keyboard.
- The system sidebar toggle is removed at every width (`.toolbar(removing: .sidebarToggle)`), as Messages shows none; View > Hide Sidebar (⌃⌘S, `SidebarCommands`) still works. It was first removed only in the strip (`isStrip ? .sidebarToggle : nil`), but changing the toolbar during the first layout, when the column briefly reports AppKit's default 144 pt and so reads as the strip, kept `NavigationSplitView` from applying the column's ideal width: every window opened with the sidebar at its 140 pt minimum (the Mac UI tests' 960 pt window included, run 40094061245). With the toolbar fixed, the sidebar opens at its ideal as before. New Chat stays at the leading edge of the chat column's toolbar.

## Tile

- `StripTile`: a fixed 78 x 86 pt frame (`stripTileSize`): avatar (`rowAvatarSize`, 40 pt) 15 pt from the top, 6 pt to the name, name in `.subheadline` (11 pt), `.secondary`, one line, tail truncation, centred, 4 pt side padding. Row insets zero, separator hidden. Fixed points, like the rows; the System Settings sidebar icon size does not change it (Crew's rows ignore it too).
- Selection: the system sidebar selection of the row (accent fill with white text when the window is key, grey when not), not a painted tile. Its corner radius is the system's (about 8 to 10 pt, Messages' about 12). The renders are captured from an offscreen window that is not key, so they show the grey state.
- Status on the avatar, as #143's compact badge: working green `ellipsis` (variable colour effect, honours Reduce Motion), waiting (approval, question, payment) orange `exclamationmark`, failed red `xmark`, a 13 pt circle knocked out of the avatar with a 2 pt gap. Unread: the regular row's 8 pt accent dot, its centre 5 pt left of the avatar (where the regular row puts it), vertically centred on it.
- Groups: `GroupAvatar` and the room name; no status badge (rooms have none).
- Drafts: not shown in the tile (no room, Messages shows none); the composer keeps them and the regular row shows them again when widened.
- Hover: `.help` with the full "title · role" (or the room name), since the tile truncates the name and drops the role.
- VoiceOver: one element per tile (`children: .ignore`), label "title, role" (or the title; the room name for groups), value the status ("Working", "Needs approval", "Waiting for you", "Wants to pay", "Failed", "Unread") plus "Draft" when a draft is pending and the chat is not open (groups: "Draft" or nothing). The `List` adds "selected".

## Surfaces

- **Selection, keyboard:** arrow keys move through the tiles; Return and double click open the bot in its own window (`contextMenu(forSelectionType:primaryAction:)`), now also for favourites in the strip; ⌘O works from the selected bot as today. Crew has no Find command, so there is no ⌘F to define in the strip.
- **Context menus:** the `List`'s selection menu (Open in New Window, Pin/Unpin, Duplicate, Move to Section, Delete) on bot tiles, favourites included. Group tiles have no menu, as group rows today. The leading swipe to pin is iOS's; the Mac strip has none, as the Mac rows have none in practice.
- **Chat, inspector, composer, push, chat windows:** untouched. A push that selects a bot selects its tile; the inspector still opens from the persona pill.
- **Connection pill:** too wide for the strip, so the strip shows `ConnectionBadge` instead: the pill's icon (spinner or orange `wifi.exclamationmark`) in a 36 pt glass circle, chosen by `isStrip` (the regular sidebar and iOS keep the full pill unchanged), with the state and host as its tooltip and VoiceOver label and value; while unreachable the circle is the Retry button (hint "Retry"), while connecting it is disabled.
- **Light and dark:** system selection, system badge colours, knockout instead of painted rings; rendered in both.

## States

- **Empty, loading, error:** "No Bots", the spinner and alerts are overlays of the list, unchanged (text wraps in the 98 pt list).
- **Offline:** cached tiles with cached statuses, the icon-only pill at the bottom after the usual 2 s.
- **Long names:** one line, tail truncated, full name in the tooltip; role never shown.
- **Many bots:** the list scrolls; after a crossing it starts at the top (see Rule), the selection is kept.
- **Search active while narrowing:** see Rule; no empty-search view in the strip, results return on widening.

## iPadOS and iPhone

Messages on iPad has no strip; its rows simply get narrower. iPad keeps plain regular rows at every sidebar width (min 240, ideal 320); #143's iPad compact rows go. Accepted: in an iPad sidebar narrowed below about 300 pt a regular row truncates the name before the status label (the label is fixed size), as Messages on iPad truncates its names; at the default 320 nothing changes. iPhone is full width and unchanged.

## Tests

- Unit (`CrewTests/SidebarStripTests.swift`, replaces `CompactRowTests.swift`), with the recorded `cold-open` roster:
  - The bot tile is exactly 78 x 86 pt.
  - `stripWidth` <= 140 < `stripThreshold` < 320.
  - The threshold: in a real sidebar-style `List` row (same row insets as `BotsView`), the text column at `stripThreshold` holds "Ada Lovelace" beside "Needs approval", and 8 pt narrower it does not.
  - Shown failing on `main` (none of it exists there; #143's 260 fails the threshold test with 154 < 171 pt) and with mutations (a flexible-width tile fails the size test).
  - The tile's VoiceOver label and value have no automated check: an unhosted test gets no accessibility tree (tried, `accessibilityChildren()` is empty); they are read in review.
- Renders (Mac, light and dark, `./snapshot.sh mac sidebar-compact sidebar layout`): `sidebar-compact` drags the divider to 330 and then to the strip (lands on 140) in a tall window with a selected waiting bot, pinned favourites, a photo avatar, working, failed, unread and a group, so the tile order is visible; with `-snapshotSidebarWidth 270` (a wide strip, just below the threshold) and `290` (regular rows just above it); `unreachable` with `-snapshotSidebarWidth 140` (the divider override now works for any screen) for the icon-only pill. `sidebar` and `layout` render in a 760 pt window, where the sidebar opens at 240 pt (as on `main`; lowering the chat column's ideal from 640 to 440 does not change it, measured), so they show the strip where `main` showed #143's compact rows. Saved as `docs/flows/renders/sidebar-strip-{140,270,290}-{light,dark}.png` and `sidebar-strip-offline-light.png`.
- Hands-on checks for the independent reviewer (no UI test, since the suite stays small): arrow keys and Return on a favourite tile, right-click menu on a favourite tile, the search field absent in the strip and back when widened, no sidebar toggle at any width.
- `-measure YES` on `layout` logs the window minimum 460.
