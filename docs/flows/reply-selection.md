# Reply text selection on the Mac (#51)

On the Mac a drag in a bot reply selected only the paragraph it started in: each markdown block was its own SwiftUI `Text` with `.textSelection(.enabled)`, and SwiftUI has no selection that spans views (the 27 SDK adds none, and `Text` ignores paragraph attributes such as head indents, so one merged `Text` would flatten lists and lose the code box). Now each reply is one read-only AppKit text view, like a Notes note or a Mail message body, so a drag runs through paragraphs, headings, list items, quotes and code blocks.

## Where

- A new Mac-only view (`ReplyText`) replaces `MarkdownText` at the two reply sites in `TurnView` only: the reply and a steer's answer. `TurnView` is shared, so this covers bot chats, group rooms (replies under a member's name), the mention peek's chat window, Other Conversations in the inspector and search results scrolled into a turn.
- `MarkdownText` itself is untouched: work log notes and thinking rows keep it, with the `.subheadline` and `.secondary` styling they set from outside.
- iPhone and iPad are unchanged: replies stay SwiftUI `Text` blocks, and long press, Select already opens the whole reply in the selection sheet. That sheet shows the raw markdown source (known gap, not part of #51).

## Mac reply

- One `NSTextView` (TextKit 1, not editable, selectable, transparent, no scroll view of its own) per reply segment. A segment is the text between A2UI cards; a reply without cards is one segment, a reply that is only a card has none. Cards stay SwiftUI `SurfaceBlock`s between the segments, and a selection stops at them, as Messages stops at a rich link.
- Same look as before: 13 pt body, headings in the same three sizes, list markers right-aligned in secondary colour with a 20 pt step per depth and an 8 pt gap before the text (a wider marker such as "10." pushes its text right, as the old row did) and wrapped lines hanging under the text, quotes in secondary colour with the 4 pt bar, rules as a hairline, the same 12 / 4 / 16 pt block spacing, inline bold, italic, code spans and strikethrough. Links use the accent colour with no underline and the pointing hand, as SwiftUI `Text` drew them.
- Code blocks keep the rounded 12 pt `quaternarySystemFill` box with 12 pt padding and the language caption on top. The box, the quote bar and the rule are drawn by small `NSTextBlock` subclasses with colours resolved at draw time (so an appearance change applies at once); the caption is drawn in the box's top padding, so it is never selected or copied. Long code lines now wrap inside the box instead of scrolling sideways, as code does in Notes: a horizontal scroll view inside the text would split the selection.
- Tables keep today's behaviour (each cell a paragraph); a reply that fails to parse shows as plain text, as before.
- Drag, Shift-click, double-click (word) and triple-click (paragraph) select as in any AppKit text; Cmd-A selects the whole segment; Cmd-C copies. Dragging past the window edge scrolls the transcript (AppKit autoscroll through the enclosing scroll view).
- Copy writes the rendered text: a plain string (paragraphs on their own lines, list items as "• text" or "1. text" with no tab characters, code as its lines, no caption) and rich text without the label colours, so text copied in dark mode never pastes white into Mail or Pages.
- Right-click on the text shows one menu: Crew's Copy Message and Share Message on top (the whole reply's markdown, with `<a2ui-json>` tags in their fenced form), then the system text menu without its editing items (Copy, Look Up, Translate, Share, Speech, which act on the selection; no Cut, Paste, Font, Spelling or Substitutions). The 12 pt padding ring around the text keeps the SwiftUI message menu (Copy, Share) as before; one menu per bubble is the follow-up if the two feel different.
- Links open on click in the default browser, or with `NSWorkspace` for other schemes, as before (PLAN: the Mac keeps the default browser). Automatic link and data detection is off, so bare URLs behave as before.
- The selection clears when the reply's text view resigns first responder (clicking another reply, the composer or a field), like Mail; clicking empty transcript space leaves it. A window going inactive greys it, as AppKit does. A selection never crosses into the next message (the issue's "ideally"; out of scope), and a reply that the lazy transcript unloads far off screen loses its selection.
- Keyboard: replies are not Tab stops (`canBecomeKeyView` false), so Full Keyboard Access skips them. Cmd-F stays the sidebar search: no find bar or find panel in replies. After clicking a reply, typing needs a click in the composer, as with the selectable `Text` before; Page Up/Down and arrow keys then go to the reply's text view (to check on the Mac build).
- Drops: the text view registers no drag types, so a file dropped on a reply still reaches the chat's attachment drop.
- VoiceOver reads each segment as one text area, by line, word or paragraph, with links in the rotor. The drawn code caption is not read (accepted: the code text itself is).
- The timestamp swipe, its fading backdrop, the hover tooltip, scroll wheel and the jump arrow still work over replies: the text view has no scroll view, so vertical scrolling passes to the transcript and `TrackpadSwipe` still sees horizontal swipes (there are no nested horizontal scroll views in Mac replies any more).

## States

- Streaming: the text storage is replaced only when the reply text changes, and the selection is put back by character offset, clamped to the new length (it can shift by a few characters when a later delta closes inline markup before it); re-renders that don't change the text (timestamp swipe frames, scrolling) never touch it.
- Long replies and long chats: the attributed text is built once per text change and the measured height is cached per width, so scrolling and column resizes don't rebuild or re-measure unchanged replies; the transcript stays a `LazyVStack`.
- Empty reply: no text view, as before. Error, Stopped, offline: unchanged rows around the reply; the reply stays selectable offline.
- Light, dark and Increase Contrast: all colours are system dynamic colours.
- Bot list (preview, time, status, unread), push and inspector content: unchanged.

## PLAN.md

- Decisions: a line for the Mac reply view (this spec), and the `TrackpadSwipe` line no longer lists code blocks as nested horizontal scroll views on the Mac. No locked UI value changes (timestamp formula, margins, jump arrow untouched).

## Verification

- `CrewTests` (macOS) builds the reply from recorded replies (`chat.steer-answer.history.json` code fence, the hike checklist heading and list from `sessions.search.weather.v0.22.2.json`, `chat.a2ui-recipe.v0.21.7.md` paragraph plus card) and asserts the segments, list markers, code text, the link attribute and the excluded caption; then, in a real `ReplyText` text view, selects across paragraphs, a list and a code block and copies to a private pasteboard (never the general one): plain text with no tabs, rich text with no label colour in dark appearance; a streaming update keeps the selection; right-click menu has Copy Message plus the system items.
- Code text is the exact ASCII the bot sent: copied code keeps `-` and `--` byte for byte, and each is drawn with the monospaced font's `hyphen` glyph (no dash or quote substitution). SF Mono's hyphen is wide, so it can read as a dash; the old `MarkdownText` drew the same glyph (`docs/flows/renders/reply-selection-code-before-dark.png` and `-after-dark.png`).
- A macOS UI test is not possible here: `CrewUITests` runs only on the iOS simulator and Crew's rules forbid driving Mac windows. The pasteboard tests are the Mac proof.
- Renders, light and dark: the real `ReplySegmentText` hosted in `NSHostingView` with headings, nested and ten-item lists, quote, rule, a wrapping code line with caption, inline code, strikethrough and a link (`docs/flows/renders/reply-selection-light.png`, `-dark.png`), compared with the old `MarkdownText` rendered the same way. The real Mac window from `-snapshot`: `chat-selection` (a selection from a paragraph through a heading into a nested list, grey because the offscreen snapshot window is never key; `reply-selection-app-*.png`), `chat-timestamps` at 560 pt with the timestamp column beside the replies (`reply-selection-timestamps-*.png`) and `chat-worklog` with the code box in the app (`reply-selection-code-app-*.png`). The right-click menus on the text and on the ring are not rendered: a context menu only appears through a real `NSMenu` popup, which tracks the user's mouse and keyboard on screen, so the menu items are covered by `rightClickOffersMessageActionsAndTheTextMenu`; the menus, the hover tooltip and keyboard scrolling are left for the check on the Mac build.
- An independent reviewer uses the Mac build from the user's side.
