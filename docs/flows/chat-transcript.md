# The transcript opens at the latest message, stays there and scrolls smoothly (#150, #107, #123, #145)

On iPhone (v0.1.29, the same on v0.1.28) a long chat lags, opens far up from the latest message, and with the keyboard up the latest reply sits under the composer and keyboard while the Jump to Latest arrow hangs over a "Worked for" row and does nothing when tapped. Sending while scrolled up leaves the new reply off screen (#123). The target is Messages: the conversation opens at the newest message, stays pinned there while replies stream and the keyboard comes and goes, leaves the reader alone when they scroll up to read, and one tap on the arrow brings them back.

## Causes

Measured on an iPhone 18 Pro simulator (iOS 27) with about 500 recorded real rows loaded half a second after the chat appears, like `ChatSession` does; identical on v0.1.28 and v0.1.29:

- **Scrolling is spread over two APIs and five manual pins.** `ChatView` scrolls with `ScrollViewReader.scrollTo` to a bottom sentinel on load, on send, on every transcript change while `isAtBottom`, when the bar's inset grows and when A2UI blocks arrive, binds a `ScrollPosition` (only fixtures and the Mac layout snapshot set it), uses `.defaultScrollAnchor(.bottom)`, and scrolls to search hits twice after sleeps. The pins all read a hand-rolled `isAtBottom`, so a wrong reading (#145's Mac probe layouts, a fling still settling) skips them, and with hundreds of rows the sentinel pin did not land: a send while scrolled up left the new reply 768 pt below the composer.
- **The arrow can't be tapped.** It is an overlay of the `safeAreaBar` content, drawn 12 pt above the bar's own bounds, so taps land outside its host: 12 of 12 taps did nothing. That screen (arrow over "Worked for", reply text under the glass composer and keyboard) is the user's screenshot. The text faintly showing through the field is the documented look (no bottom scroll edge effect, a 0.85 fill behind the field); it only reads as broken because the view is not at the bottom.
- **Opening far up:** not reproduced with short recorded rows (both versions open 45 pt from the end). The final simulator pass measures cold and cached opens with `Tests/fixtures/chat.long-replies.history.json` (six long Markdown replies recorded on `crew-test` with `Tests/chat_probe/run.sh long-chat`, repeated to about 500 rows) on v0.1.29 and on the new container; the PR states the measured cause or that it did not reproduce.
- **Every redraw re-parses every visible reply.** `MarkdownText` (iOS) and `ReplyText` (Mac, through `replySegments`) parse their Markdown in `body` (0.3 to 2.5 ms per long recorded reply on an M-series Mac, optimised). `TurnView` takes closures, so SwiftUI redraws every materialised turn whenever `ChatView`'s body runs: on each streaming delta, keyboard animation frame (`barRoom`), `isAtBottom` flip and timestamp swipe step, and the lazy stack parses again each time a row scrolls into view.

### What SwiftUI does on its own (macOS host, Xcode 27 SDK)

Measured with AppKit's scroll view, so every iOS claim below also has an iOS UI test. An offscreen window with `ScrollView` + `LazyVStack` (300 wrapped rows of mixed height) + `.scrollTargetLayout()` + `.defaultScrollAnchor(.bottom)` + `.scrollPosition` + a `safeAreaBar` (`Tests/CrewTests/ScrollAnchorExperimentTests.swift`, user scrolls sent as phased scroll-wheel events):

- Cold (empty, then 300 rows): opens at the bottom (distance 0).
- At the bottom: the last row growing, a row appended and the bar growing by 100 or 200 pt all keep the end in view (distance 0), also after the user scrolled up and back down by hand while `ScrollPosition` held a view id (it held 298 and 299). PLAN.md's earlier finding that new turns landed below the composer once the position held an id (seen on iOS) does not reproduce on macOS; the iOS UI tests below check it.
- Scrolled up 1500 pt: the last row growing and a row appended move the reading position by 0 pt, and a row expanding inside the viewport while a view id is held (row 151) grows downward (0 pt). The bottom anchor only holds the end when the reader is at the end, so one `.defaultScrollAnchor(.bottom)` covers every role; no per-role split is needed.
- `scrollTo(edge: .bottom)`, plain or in `withAnimation`, from 32 000 pt up lands at the end, and its edge state then holds the end through appends and bar growth with no overshoot. Without `.scrollTargetLayout()` the animated jump stayed where it was, so the layout keeps it.
- `scrollTo(id:anchor: .center)` centres a laid-out row exactly (264 to 376 of 640 pt), and issued in the same update that delivers the rows it brings the row into view (502 to 582 of 640).

PLAN.md measured `scrollTo(edge: .bottom)` scrolling twice the keyboard height when the keyboard raised the bar's inset (588 pt for a 294 pt keyboard). The keyboard only exists on iOS, so that is re-measured in the simulator pass (keyboard up and down after an edge jump). If it still overshoots, the jumps target the last turn's id with `.bottom` instead, a one-line change, and PLAN.md says so.

## The change

Two independent pull requests.

### 1. Parse each reply once

`markdownBlocks(from:)` and, on Mac, `replySegments(from:)` (the attributed text built from the blocks, which cost more than the parse: about 0.9 ms per long reply) keep their results in a `ParseCache`, an `NSCache` keyed by the source text with a 4 MB cost limit by text size (the `CachedImage` precedent), so a redraw or a row scrolling back in reuses them on iOS and on Mac. A streaming reply still parses once per delta, and those prefixes age out by cost. `a2uiFenced` skips its regex when the reply has no `<a2ui-json>`. Nothing visible changes.

### 2. One scroll container on the standard idiom (iOS and Mac together)

- A new `TranscriptScroll` view (its own file, compiled into CrewTests too) wraps `ScrollView` with `.defaultScrollAnchor(.bottom)`, `.scrollPosition` on one `ScrollPosition` owned by `ChatView`, the at-bottom reading and the arrow. `ChatView` puts the `LazyVStack` of turns with `.scrollTargetLayout()` inside it and keeps every other modifier as today.
- Deliberate jumps go through that `ScrollPosition`: the arrow (animated, no animation with Reduce Motion) and Send, Steer and Queue scroll to the bottom edge; a search hit scrolls to its turn centred; a fixture's `scrollTarget` to its turn at the top. No `ScrollViewReader`, no bottom sentinel, no `Task.sleep`.
- No pins on transcript changes, A2UI blocks, bar growth or keyboard: the measurements above show the bottom anchor keeping the end in place while the reader is there. A pin comes back only where an iOS UI test fails without it, and this spec and PLAN.md then name it. Named fallbacks: if a turn arriving after a manual return lands under the composer, `onChange(of: transcript)` scrolls to the bottom edge while `isAtBottom`; if the keyboard overshoots after an edge jump, jumps target the last turn's id.
- `isAtBottom` (within 40 pt of the end, from `onScrollGeometryChange`) lives in `TranscriptScroll` and only shows and hides the arrow. The search hit no longer writes it; the geometry does.
- Search hits: on `focus` or on the turn count changing (history arriving after the hit, as today), when the focus is new and its turn is found, one `scrollTo(id:anchor: .center)`, then `handledFocus` and the 2 s tint as today.
- Fixture scroll targets keep their trigger (`surfaces.blocks.count`, so card heights exist first) and drop the bottom-pin branch. Used by the `chat-history`, `chat-timestamps`, `chat-worklog`, A2UI fixtures and the Mac `layout-inspector` snapshot.
- The arrow is a bottom overlay of the scroll view, applied inside the `safeAreaBar`, so its safe area excludes the bar (with the bar's `.ignoresSafeArea(.container, edges: .bottom)` and the keyboard on iOS). It sits 12 pt above the top of the composer bar and any card in it (locked value, unchanged) and is hit-tested with the scroll view. On Mac it takes the composer's legacy-scroller trailing padding, so it centres on the composer. Same glass circle, label, icon, `.controlSize(.large)` on Mac, scale and fade, the animation scoped to the arrow.
- Removed: `JumpToLatest.swift`, `BottomEdge`, `bottomID` and the sentinel, the five pins, the focus sleeps.
- Kept as is: `HeightCap` and `barRoom`, the composer and its locked bottom offsets, `.ignoresSafeArea(.container, edges: .bottom)`, swipe timestamps (iOS `DragGesture`, Mac `TrackpadSwipe`, `revealsTimestamps`), `.scrollDismissesKeyboard(.interactively)`, the drop destination, the empty-state overlay, the top soft edge effect and the hidden bottom one, the persona pill clearing focus before the inspector.
- Out of scope: `ConversationTranscript` (the inspector's read-only conversation view) keeps its own `ScrollViewReader`; it has no composer, keyboard or streaming.
- PLAN.md: Decisions lines on the sentinel (66), the bar re-pin (last sentence of 88), "Keyboard and scrolling" (157, keeping the persona pill sentence) and #103's bar animation rule (160, which names `JumpToLatest`) give way to one line for this design; lines 59 and 62 stop contradicting line 27 (no bottom edge effect; the fill dims what scrolls under the field).

## Surfaces and directions

- **Bot chat, iPhone (`ChatScreen`, opened from the list, a push tap or search; also inside the mention peek's large detent):** opens at the latest message, cold (empty, then history arrives) or cached (`ChatSessions` already holds it), with no visible scroll animation.
- **Mac main window chat column and the separate chat window (`BotChatWindow`):** the same container; live resize with the inspector attached keeps the transcript at the bottom and the arrow hidden when the reader was at the bottom (#145).
- **Group rooms (`GroupChatScreen`):** same container; the welcome empty state shows with no arrow.
- **Sender:** Send, Steer and Queue scroll to the bottom first, so the new bubble (or the outlined Waiting or Queued bubble) sits right above the composer, keyboard up or down, then the reply streams in below it and stays pinned.
- **Receiver (replies back):** a reply streaming, a work log growing, a turn from another client or a bot-to-bot notice, and the post-turn history reload that adopts server ids keep the latest row in place while the reader is at the bottom.
- **Reader scrolled up:** none of the above moves what they are reading; the arrow shows. A send still brings them to the bottom, like Messages.
- **Keyboard:** raising or lowering it while at the bottom keeps the latest row right above the composer; while scrolled up it leaves the reading position alone and the arrow stays usable above the bar.
- **Composer bar grows (multi-line draft, attachment tray, mention picker, dictation, offline line, approval, question, payment, offer or notice card, up to `HeightCap`):** at the bottom the latest row stays above the bar.
- **Search hit (`SearchFocus`):** the matched turn scrolls into view near the centre and is tinted for 2 s, even 500 rows up.
- **Work log or reply expanded mid-transcript:** it grows downward from the tapped header.
- **Bot list (preview, time, status, unread), push, inspector:** untouched; no model, request or network change.
- **Light and dark:** the arrow keeps its glass look; no other visual change.

## States

- Empty chat: empty state (or room welcome), no arrow.
- Long chat (500 rows, long Markdown replies, code blocks, A2UI cards): opens at the bottom, scrolls without hitches, Jump to Latest lands at the end from the top in one tap.
- A reply taller than the screen streaming at the bottom: the end of the text stays above the composer.
- Mid-stream jump: lands at the bottom and stays pinned as the reply grows.
- Offline and error turns: unchanged; the arrow and jumps still work offline.
- Rotation, iPad split view and Mac window resizes: container size changes keep the bottom anchored.
- VoiceOver: the arrow reads "Jump to Latest". Reduce Motion: the jump is not animated.

## Tests

Host unit tests (macOS), each shown failing first:

- `ReplyParseTests`: redrawing the six recorded long replies 20 times takes under a quarter of parsing them 20 times, for the blocks and for the Mac segments, measured in the same run; fails with the cache bypassed.
- `TranscriptScrollTests` (the real `TranscriptScroll`, rows of mixed height, a `safeAreaBar`; it replaces the print-only `ScrollAnchorExperimentTests`, which is deleted): cold open at the bottom; at the bottom a growing last row, an appended row and a growing bar keep the end in view; scrolled up, the same changes and a mid-row expansion move the reading position by under 1 pt; scrolled back down by hand, an appended row stays in view; the arrow's action from 30 000 pt up lands at the end; a search jump into rows that arrive in the same update brings the row into view. The pins-and-sentinel composition (today's `ChatView`, as `ComposerResizeTests` copies it) fails the jump and resize cases.
- `ComposerResizeTests` is rewritten to host `TranscriptScroll` instead of its copy and gains #145's check: after the resize steps with the inspector attached (main window and chat window), the transcript is at the end and the arrow is not in the accessibility tree; fails with the copied old composition.

UI tests (iOS, `composer-line` loading the recorded long replies after the chat appears), each shown failing on the v0.1.29 build and passing after:

- Opens with the latest reply right above the composer, cold (the fixture delivers history after the chat appears); still there with the keyboard up and after it goes down. If this fails on the new container, #150's "opens far up" is not fixed, whatever v0.1.29 did.
- Scrolled up, a reply from another client streams in (`-replyAfterDraft`, the fixture's stand-in for a turn picked up from the server): the row being read does not move, and tapping a visible "Worked for" header expands it downward (its header does not move).
- Scrolled up, then back down by hand (no arrow), a reply from another client streams in: it ends right above the composer and no arrow shows.
- Keyboard up, scroll up, tap Jump to Latest, three times: the latest reply is right above the composer and the arrow is gone (#107); then keyboard down, still right above.
- Scrolled up, send: the new bubble and its reply sit right above the composer (#123).
- `ChatSendScrollUITests` (steer, queue, multi-line, short rows) stays and must pass unchanged.

Simulator pass, same session:

- Lag: `XCTOSSignpostMetric` scroll dragging and deceleration hitch time ratio on the long fixture, v0.1.29 build against each pull request. Simulator ratios are a relative signal only; pass means lower than v0.1.29.
- Keyboard up and down after an edge jump with no overshoot (the PLAN.md 588 pt case).
- Renders, iPhone light and dark: long chat at the bottom with the keyboard up; scrolled up with the arrow; the arrow with a question card in the bar (`chat-question`); `chat-history` and `group-welcome`.
