# Pre-release QA: small visual fixes

Five small fixes found in pre-release QA. Each keeps SwiftUI's standard pieces; no new mechanisms.

## Surfaces

- **Connection names** (inspector Connections rows, remove confirmation, Add Connection catalog rows and detail title, New Bot Advanced connection list, monogram tile): the server's name exactly as configured (`icloud` stays `icloud`). The catalog carries no display name, so catalog entries show their `name` too. No capitalization guessing, no brand map.
- **Other conversation sheet** (search result or inspector conversation opened as a sheet): Mac shows the conversation title in the sheet's toolbar, like iPhone's inline title. Untitled conversations read "Untitled".
- **Add Connection sheet** (Mac): a grouped Form like Add Login and New Group, with the search field as the first row of the sheet's content (a Mac sheet's `.searchable` toolbar puts it in a separate strip above the title). iPhone keeps `.searchable` in the navigation bar. **Custom Connection** already matches Add Login (the leading-aligned sheet title is macOS 27's standard sheet toolbar), so it is unchanged.
- **Tasks and Routines empty states** (inspector tabs): "No Tasks", "No Routines", "Couldn't Load Routines" and the loading spinner show on the plain grouped background on both platforms, never inside a grey rounded row.
- **Connection errors** (inspector Connections): the red status or failure text is at most two lines; the full text is the row's tooltip on Mac and the title of the row's context menu on iPhone and Mac. VoiceOver reads the full text.

## States

- Empty, loading and error states for Routines keep their wording; only the container changes.
- Long content: long server names truncate in the middle on one line; long errors clamp to two lines with an ellipsis.
- Light and dark, iPhone and Mac, checked in renders: `other-conversation`, `add-connection`, `custom-connection`, `inspector-routines-empty`, `inspector-connections` (Tasks empty uses the same Section-header container; no fixture renders it).
