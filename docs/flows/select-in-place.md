# Select text in place on iPhone and iPad

User report (v0.1.50): long press, Select on a message opens a full-screen "Select Text" sheet that shows the raw markdown (backticks around `/reload-mcp`). In Messages, long press, Select selects the bubble's text where it is: the whole text highlighted, two grab handles and the system edit menu (Copy, Look Up, Translate, Share, …), with the conversation still in view.

## Why a UIKit text view

- SwiftUI on iOS 27 has no range selection on `Text`. `.textSelection(.enabled)` "lets people select text in a platform-appropriate way" (SwiftUI.swiftdoc); on iOS that is a long-press menu that copies the whole string, no handles, and it competes with the message's own `.contextMenu` long press. `TextSelection` and `AttributedTextSelection` (SwiftUI.swiftinterface, iOS 27.2 SDK) bind only to `TextField` and `TextEditor`, which are editable. `TextSelectability` (SwiftUICore) has only `enabled` and `disabled`.
- The only native in-place range selection on iOS is a non-editable `UITextView`, which is what Messages, Notes and Mail use. It is used through `UIViewRepresentable` (a standard bridge, no reach-ins), and only while one message is in select mode, so the transcript keeps its SwiftUI `Text` rows for scrolling and streaming.
- The sheet dates from Crew 0.1.0 (e492971), as the cheapest way to get any selection on iOS; `reply-selection.md` already listed its raw markdown as a known gap.

## Where

- Every place with the message menu's Select: user bubbles (sent, steer, queued), bot replies, a steer's answer and a slash command's output box. `TurnView` is shared, so bot chats, group rooms, the mention peek's chat, Other Conversations and search results all get it.
- iPhone and iPad only. The Mac keeps its own selection (`ReplyText` text views, `.textSelection` on bubbles) and has no Select item; nothing changes there.

## Flow

1. Long press a message: the context menu as today (Copy, Select, Share, Remove from Queue for a queued message).
2. Select: the menu closes, and that message's text is selected in place, whole, with handles and the system edit menu above it, like Messages. No haptic (Messages plays none). The message keeps its place and look; its height changes only where select mode lays out differently (a long code line wraps, a mention tag loses its avatar). The keyboard goes down if it was up (the selection takes first responder, as in Messages). VoiceOver focus moves to the selected text.
3. Drag a handle to change the range; the edit menu follows and offers the system items for the selection (Copy, Look Up, Translate, Share, and others the system adds). While selecting, the message's context menu and the timestamp swipe are off for that message, so a long press or a handle drag goes to the text.
4. Copy writes plain text of what is shown: no markdown syntax, list items as "• text" or "1. text" without tab characters, code as its lines without the caption, a mention as "@ Name". No rich text, so text copied from the white bubble never pastes white.
5. Select mode ends when: the selection is cleared by a tap inside the text, a link in it is tapped (the link also opens), the transcript is tapped elsewhere, the composer is focused, Select is chosen on another message, the row leaves the transcript (removed from the queue, unloaded far off screen) or the chat closes (back, another chat in the iPad sidebar). The message then goes back to its normal view. Backgrounding the app keeps it, as UIKit keeps a selection.
6. Scrolling the transcript keeps the selection (Messages does too). Dragging a handle to the screen edge does not scroll the transcript (the text view has no scroller of its own inside the SwiftUI scroll view); to select past the screen, scroll and drag again. Known limitation, in PLAN.

## Look in select mode

The text view draws the same rendering as the normal view, from the same parsed markdown: never raw markdown.

- Bot reply: 17 pt body; headings in title2/title3/headline bold; bold, italic, strikethrough and inline code (monospaced) runs; links in the accent colour without underline; list markers right-aligned in secondary colour, 20 pt per depth, 8 pt before the text with wrapped lines hanging under the text; quotes in secondary colour with the 4 pt bar; rules as a hairline; the same 12 / 4 / 16 pt block spacing; code blocks in the 12 pt rounded `quaternarySystemFill` box with 12 pt padding and the language caption on top (drawn, so never selected or copied). Like the Mac reply view, long code lines wrap inside the box in select mode instead of scrolling sideways (a horizontal scroller inside the text would split the selection).
- Mechanism: the attributed text comes from the same builder as the Mac reply view (`replySegments` in `ReplyTextView.swift`, shared by both platforms). The Mac draws the code box, quote bar and rule with `NSTextBlock`, which UIKit lacks; on iOS the text view uses TextKit 1 with a small `NSLayoutManager` subclass that draws those three in `drawBackground(forGlyphRange:at:)` from a marker attribute, behind the glyphs, with the same sizes and colours.
- A2UI cards in a reply stay SwiftUI cards between text segments; a selection stops at a card, as in Messages at a rich link. Select on a reply with several text segments selects the first one; a reply with no text (only a card) and empty command output have no Select item.
- Data detectors are off, so bare URLs, dates and numbers behave as in the normal view.
- The search-result highlight is not drawn while the row is selecting.
- User bubble: white 17 pt text on the blue bubble, selection highlight and handles in white so they show on blue, as Messages does; the outlined (queued or waiting) bubble keeps blue text and blue handles on the plain background. A mention tag shows as "@ Name" in semibold without its small avatar while selecting (the avatar is an inline image, not text).
- Slash command output: its code box as above.

## Behaviour

- Links in the selected text open on tap through the app's `openURL` (in-app Safari for web links), as outside select mode.
- Streaming: Select on a reply that is still streaming keeps working; new text appears in the text view and the selection stays by character offset, clamped. Finishing, an error row or a new reply below do not end it. A queued bubble that gets sent keeps select mode if its row stays (it turns filled, handles turn white). Nothing is added per token for messages not in select mode, and no text view exists for them.
- Dynamic Type and Bold Text: fonts come from `UIFont.preferredFont(forTextStyle:)` when select mode starts and are rebuilt on a size change, so they match the normal view at every size.
- iPad: pointer click-drag, hardware keyboard Cmd-C and Cmd-A come with `UITextView`; a width change (rotation, Stage Manager) reflows with the selection kept. The iPhone renders cover iPad: same view, no iPad-only layout.
- VoiceOver: unchanged outside select mode. In select mode the text view is a static text element with the same content (VoiceOver users select through the rotor's text selection, as in Messages).
- Light, dark and Increase Contrast: system dynamic colours, and the bubble keeps its Increase Contrast blue.
- Empty, error, offline: no change; a message can be selected offline. Long content: the text view grows with the message, no inner scrolling.

## Removed

- The Select Text sheet (`SelectionSheet`) and its full-screen `UITextView`; `Chat/MessageMenu` drops off the sheet presenters allowlist in `scripts/lint-ui.sh`.

## Unchanged surfaces

- Bot list (preview, time, status, unread), push, inspector content, the timestamp swipe, work log notes: not touched.

## PLAN.md

- Decisions: a line for select in place (this spec), why a representable is used, and the Mac reply selection line no longer says iOS keeps only `MarkdownText`.

## Verification

- Unit tests: `CrewTests` runs on macOS only, so the shared builder is tested there (no backticks for the reported reply, monospaced inline code, link attribute, caption excluded) next to the existing Mac reply tests; the iOS drawing and the representable are proven by the UI test and renders.
- iOS UI test (fails on main): long press the CI reply in the `workLog` fixture (inline `macos-15`, a link and a code block), Select: no "Select Text" sheet, an in-transcript text view whose value contains "macos-15" and no backtick, still in the chat (composer visible); tap the transcript, the text view is gone. Same for a user bubble.
- `ChatTranscriptUITests` and `AccessibilityStateUITests` on a private simulator.
- `./build.sh` (iOS and Mac) with zero warnings; `scripts/lint-ui.sh`.
- Renders iPhone light and dark of a reply and a bubble in select mode, and the same screen not selecting to compare; Mac `chat-selection` light and dark to check nothing changed.
