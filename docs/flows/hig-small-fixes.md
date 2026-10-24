# Small HIG fixes (audit batch, 2026-10-24)

Seven small deviations from Apple's patterns reported by an audit; six fixed with the standard SwiftUI idiom, one (5) turned out to be correct already. No new surfaces, no locked UI values change, nothing is removed.

## 1. Disclosure chevrons follow the reading direction

- **Where:** the work-log turn header ("Worked for 2m") and each tool/thinking row (`WorkLog.swift`), and the chat preview card in the mention peek (`MentionPeek.swift`).
- **Rule:** `chevron.forward` instead of `chevron.right`. Collapsed it points along the reading direction (right in English, left in Arabic and Hebrew); the work-log ones keep their 90° rotation when open, which points down in both directions (checked with an `ImageRenderer` probe: SwiftUI mirrors the rotation in right-to-left layout). The peek card's chevron is a navigation chevron and does not rotate, like a `NavigationLink` row's.
- **Unchanged:** the Mac carousel's Previous/Next arrows are not part of this batch (whether the carousel's paging mirrors in right-to-left is a separate question).
- **Surfaces:** chat transcript (every chat, rooms included) and the mention peek, iPhone and Mac, light and dark. In English nothing looks different, so the proof is a forced right-to-left Mac render (`-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES`) of `chat-worklog`: closed rows point left, open ones down (`renders/hig-small-fixes-chat-worklog-mac-rtl.png`). The peek card uses the same symbol without rotation; no snapshot shows it on the Mac.

## 2. Work rows tell VoiceOver whether they are open

- **Where:** tool and thinking rows in an expanded work log. The turn header already reads "Expanded"/"Collapsed".
- **Rule:** the row's `Button` in `WorkRow` (not its container, so the details below don't inherit it) gets the same value, `Expanded` or `Collapsed`, so VoiceOver reads "Thinking, …, button, Collapsed" like a `DisclosureGroup`. Notes (plain text lines) are not buttons and get nothing.

## 3. An open Thinking row says its text once

- **Today:** a thinking row shows "Thinking" plus the first line of the thought as its one-line summary; opened, the body shows the whole thought, so the first line appears twice.
- **Rule:** like a `DisclosureGroup` whose label stays put while the content appears (and Mail's collapsed thread message, whose preview line goes when it opens), the summary shows only "Thinking" while the row is open and the full thought sits below it. Collapsed it keeps the preview. The body is not shortened: thoughts are often one paragraph that the one-line summary truncates, so dropping the first line from the body would lose text.
- **Tool rows:** unchanged. Their subject (command, path) also appears inside the raw arguments JSON in the body; that is the tool's exact input, shown for inspection like a log, not a repeat of prose, so it stays.
- **VoiceOver:** the label follows what is shown: "Thinking, The CI failure is…" collapsed, "Thinking" open with the thought as the next element.
- **States:** an empty thought reads "Thinking" both ways; a one-line thought opens to "Thinking" over that line; a long, multi-paragraph thought as today below the header; streaming thoughts update the body as today.

## 4. The pending-attachment remove button has a full touch target

- **Where:** the tray of pending attachments above the composer (images and file chips), iPhone and Mac.
- **Rule:** the `xmark.circle.fill` glyph keeps its size, colours and place in the top-trailing corner; its button's label is framed 44 x 44 pt, aligned top-trailing, with `.contentShape(.rect)` so the transparent part responds under the plain button style (the HIG minimum on iOS), extending into the thumbnail, which has no action of its own in the tray. VoiceOver label stays "Remove <name>". The Mac gets the same region; it is larger than the Mac minimum and harmless since the thumbnail does nothing on click either.
- **Glass:** dropped. The file chip's `glassEffect` sits on the transcript (the bottom bar has no glass background; glass in the composer is only on the field and its round buttons), so it is a single glass layer, not glass in glass.
- **States:** several attachments in a row: each target lies within its own item (images are 64 pt, chips 64 pt high), so targets never overlap; long file names truncate as today.

## 5. New Group members: dropped, already selected for VoiceOver

The audit read the hand-drawn checkmark circles as carrying no selected state. The iOS accessibility tree (dumped from a UI test on the New Group sheet) shows otherwise: a picked row's button is already `Selected`, inferred by SwiftUI from the `checkmark.circle.fill` symbol, and its label is just the bot's name ("Forge"), so VoiceOver reads "Forge, selected, button"; an unpicked row reads "Ledger, button". `List(selection:)` would not fit either (a `Form` with other sections, pick order feeds the default name, rows disable individually, iPhone multi-select needs edit mode). No change.

## 6. Carousel page dots use label colours

- **Where:** the A2UI Carousel's page indicator (`docs/flows/a2ui-carousel.md`).
- **Rule:** the current dot uses the system label colour and the others the tertiary label colour (`UIColor.label`/`.tertiaryLabel`, `NSColor.labelColor`/`.tertiaryLabelColor`), the same colours `UIPageControl` derives its defaults from, instead of black or white picked from the colour scheme. These are concrete dynamic colours, so they stay crisp inside the glass card (the hierarchical `.primary`/`.tertiary` styles render vibrant grey there, which is why the original spec avoided them), and they follow Increase Contrast. Size (7 pt), spacing and the 28 pt full-width hit area are unchanged; the page-indicator bullet in `a2ui-carousel.md` is rewritten to name the label colours.
- **Check:** the dark render of `chat-a2ui-carousel`: the current dot must stay clearly white against the card. If it turns grey, the item is dropped and the doc keeps black/white.

## 7. The New Bot header shows only what was typed

- **Today:** the large header under the avatar reads "New Bot" until a name is typed, repeating the sheet's title.
- **Rule:** like Contacts' new-contact sheet, no placeholder name sits under the avatar; the name (or the display title, or the profile id) appears under it as the user types, and the role below it as today. The name's line keeps its height while empty (an invisible, VoiceOver-hidden line), so the first keystroke doesn't push the Name field down under the caret.
- **States:** empty: avatar over a blank line; role typed without a name: avatar, blank line, role; name typed: the name; display title typed: the title; invalid name: the header follows the name and the footer shows the problem as today.

## Verification

- iOS UI test (one file, one launch per screen, CI after merge; UI tests because VoiceOver values and real hit regions are only observable through XCUITest, an `NSHostingView` exposes no accessibility tree in a unit test): a work row reports Collapsed, becomes Expanded on tap, and an open Thinking row's label is just "Thinking" (fails today: no value, label repeats); the remove button in `chat-attachments` is at least 44 x 44 pt and a tap near its region's bottom-leading corner removes the attachment (fails today: 20 pt). Both shown failing on a private simulator before the fix and passing after; 
- Renders, macOS and iOS, light and dark: `chat-worklog` (chevrons, open Thinking row), `chat-attachments` (glyph position unchanged), `chat-a2ui-carousel` (dots), `new-bot` (avatar only); macOS right-to-left `chat-worklog`. iOS light and dark committed to `docs/flows/renders/hig-small-fixes-*`.
- `./build.sh` with zero warnings.
