# The transcript opens at the latest message, stays there and scrolls smoothly (#150, #107, #123, #145)

On iPhone (v0.1.29, the same on v0.1.28) a long chat lags, opens far up from the latest message, and with the keyboard up the latest reply sits under the composer and keyboard while the Jump to Latest arrow hangs over a "Worked for" row and does nothing when tapped. Sending while scrolled up leaves the new reply off screen (#123). The target is Messages: the conversation opens at the newest message, stays pinned there while replies stream and the keyboard comes and goes, leaves the reader alone when they scroll up to read, and one tap on the arrow brings them back.

## Causes

Measured on an iPhone 18 Pro simulator (iOS 27) with about 500 recorded real rows loaded half a second after the chat appears, like `ChatSession` does; identical on v0.1.28 and v0.1.29:

- **Scrolling is spread over two APIs and five manual pins.** `ChatView` scrolls with `ScrollViewReader.scrollTo` to a bottom sentinel on load, on send, on every transcript change while `isAtBottom`, when the bar's inset grows and when A2UI blocks arrive, binds a `ScrollPosition` (only fixtures and the Mac layout snapshot set it), uses `.defaultScrollAnchor(.bottom)`, and scrolls to search hits twice after sleeps. The pins all read a hand-rolled `isAtBottom`, so a wrong reading (#145's Mac probe layouts, a fling still settling) skips them, and with hundreds of rows the sentinel pin did not land: a send while scrolled up left the new reply 768 pt below the composer.
- **The arrow can't be tapped.** It is an overlay of the `safeAreaBar` content, drawn 12 pt above the bar's own bounds, so taps land outside its host: 12 of 12 taps did nothing. That screen (arrow over "Worked for", reply text under the glass composer and keyboard) is the user's screenshot. The text faintly showing through the field is the documented look (no bottom scroll edge effect, a 0.85 fill behind the field); it only reads as broken because the view is not at the bottom.
- **Opening far up and blank screens:** with the long recorded replies (`Tests/fixtures/chat.long-replies.history.json`, recorded on `crew-test` with `Tests/chat_probe/run.sh long-chat`, repeated to about 500 rows) v0.1.29 opened at the end in the simulator, so the user's "far up" did not reproduce there. What did reproduce is the family behind it: the bottom anchor positions against the `LazyVStack`'s estimated height, so without a pin the anchor alone left 150 pt of blank space under the last reply on a cold open, and a cached open (`layout` snapshot) whose scroll view first got its size during the push drew nothing at all although the geometry reported the end in view.
- **Every redraw re-parses every visible reply.** `MarkdownText` (iOS) and `ReplyText` (Mac, through `replySegments`) parse their Markdown in `body` (0.3 to 2.5 ms per long recorded reply on an M-series Mac, optimised). `TurnView` takes closures, so SwiftUI redraws every materialised turn whenever `ChatView`'s body runs: on each streaming delta, keyboard animation frame (`barRoom`), `isAtBottom` flip and timestamp swipe step, and the lazy stack parses again each time a row scrolls into view.

### What SwiftUI does on its own (macOS host, Xcode 27 SDK)

Measured with AppKit's scroll view, so every iOS claim below also has an iOS UI test. An offscreen window with `ScrollView` + `LazyVStack` (300 wrapped rows of mixed height) + `.scrollTargetLayout()` + `.defaultScrollAnchor(.bottom)` + `.scrollPosition` + a `safeAreaBar` (an experiment since folded into `TranscriptScrollTests`, user scrolls sent as phased scroll-wheel events):

- Cold (empty, then 300 rows): opens at the bottom (distance 0).
- At the bottom: the last row growing, a row appended and the bar growing by 100 or 200 pt all keep the end in view (distance 0), also after the user scrolled up and back down by hand while `ScrollPosition` held a view id (it held 298 and 299). PLAN.md's earlier finding that new turns landed below the composer once the position held an id (seen on iOS) does not reproduce on macOS; the iOS UI tests below check it.
- Scrolled up 1500 pt: the last row growing and a row appended move the reading position by 0 pt, and a row expanding inside the viewport while a view id is held (row 151) grows downward (0 pt). The bottom anchor only holds the end when the reader is at the end, so one `.defaultScrollAnchor(.bottom)` covers every role; no per-role split is needed.
- `scrollTo(edge: .bottom)`, plain or in `withAnimation`, from 32 000 pt up lands at the end, and its edge state then holds the end through appends and bar growth with no overshoot. Without `.scrollTargetLayout()` the animated jump stayed where it was, so the layout keeps it.
- Holding a turn's id does not follow that turn's growth (188 pt behind).
- `scrollTo(id:anchor: .center)` centres a laid-out row exactly (264 to 376 of 640 pt), and issued in the same update that delivers the rows it brings the row into view (502 to 582 of 640).

### What iOS does differently (iPhone 18 Pro simulator, iOS 27)

The macOS numbers did not all carry over; each line has a UI test that failed until the change in the next section:

- An edge jump followed by content growth with the keyboard up overshoots by about a keyboard height: a send from far up left a blank transcript (#123 on the rebuild, the PLAN.md 588 pt finding). Edge state must not stay behind.
- `ScrollViewReader.scrollTo` from far up into a long `LazyVStack` lands short (a send and every Jump to Latest failed with it), and its geometry-fired pins corrupt the Mac probe layouts (707 pt off at rest, #145).
- After the reader scrolls back down by hand, the anchor alone does not follow a reply that arrives (2 of 3 runs), and content that grows at the end while nothing scrolls (a question card's turn, rows measured late) is not followed either.

## The change

Two independent pull requests.

### 1. Parse each reply once

`markdownBlocks(from:)` and, on Mac, `replySegments(from:)` (the attributed text built from the blocks, which cost more than the parse: about 0.9 ms per long reply) keep their results in a `ParseCache`, an `NSCache` keyed by the source text with a 4 MB cost limit by text size (the `CachedImage` precedent), so a redraw or a row scrolling back in reuses them on iOS and on Mac. A streaming reply still parses once per delta, and those prefixes age out by cost. `a2uiFenced` skips its regex when the reply has no `<a2ui-json>`. Nothing visible changes.

### 2. One scroll container (iOS and Mac together)

- A new `TranscriptScroll` view (`Sources/Chat/TranscriptScroll.swift`, compiled into CrewTests too) wraps `ScrollView` with `.defaultScrollAnchor(.bottom)`, `.scrollPosition` on one `ScrollPosition` owned by `ChatView`, a zero-height end sentinel after the content, the at-bottom reading and the arrow. `ChatView` puts the `LazyVStack` of turns with `.scrollTargetLayout()` inside it and keeps every other modifier as today. Every scroll goes through that `ScrollPosition`; there is no `ScrollViewReader`.
- Holding the end means `position.scrollTo(id: transcriptEnd)`: a held zero-height view at the end follows growth by construction (host and iOS tests).
- Jump to Latest animates `scrollTo(edge: .bottom)` (no animation with Reduce Motion, code path only) and, once it lands, hands the edge state over to holding the end, so the keyboard overshoot above cannot happen. The edge scroll is the only jump that lands from far up on iOS: a non-animated sentinel jump from a long slow scroll went blank, and an animated id scroll does not move on the Mac host.
- Send, Steer and Queue hold the end before sending. A search hit scrolls to its turn centred, once, when the focus is new and its turn is found (on `focus` or on the turn count changing, as today), then `handledFocus` and the 2 s tint. A fixture's `scrollTarget` scrolls to its turn at the top on `surfaces.blocks.count`, as today.
- The end is held again, each case with the test that needs it: when the scroll view first gets its size (the blank cached open); when the end moves away while the reader was within 40 pt of it, nothing is scrolling, the container did not grow and no search or fixture target is held (a card, a late-measured row or the bar at the end, a Mac chat-window resize shrinking it); when a drag or fling (not a programmatic animation) comes to rest within 40 pt of the end (a reply after a manual return); and on a transcript change while at the end and nothing is scrolling (a hold during a rubber-band bounce left the lazy stack blank). A container that grows is left to the anchor, because pins on growth corrupt the Mac probe layouts.
- "No target held" is `isPositionedByUser`, a nil view id or the sentinel's id. On iOS 27 a user scroll leaves `isPositionedByUser` false and tracks the top turn's id, so after the reader scrolls, only the rest hold re-attaches to the end.
- `isAtBottom` (within 40 pt of the end) lives in `TranscriptScroll` and drives the arrow and those holds; the search hit no longer writes it.
- The arrow is a bottom overlay of the scroll view, applied inside the `safeAreaBar`, so its safe area excludes the bar (with the bar's `.ignoresSafeArea(.container, edges: .bottom)` and the keyboard on iOS). It sits 12 pt above the top of the composer bar and any card in it (locked value, unchanged) and is hit-tested with the scroll view. On Mac it takes the composer's legacy-scroller trailing padding, so it centres on the composer. Same glass circle, label, icon, `.controlSize(.large)` on Mac, scale and fade, the animation scoped to the arrow.
- Removed: `JumpToLatest.swift`, `ScrollViewReader`, the transcript, blocks and inset pins by proxy, the focus sleeps.
- Kept as is: `HeightCap` and `barRoom`, the composer and its locked bottom offsets, `.ignoresSafeArea(.container, edges: .bottom)`, swipe timestamps (iOS `DragGesture`, Mac `TrackpadSwipe`, `revealsTimestamps`), `.scrollDismissesKeyboard(.interactively)`, the drop destination, the empty-state overlay, the top soft edge effect and the hidden bottom one, the persona pill clearing focus before the inspector.
- Out of scope: `ConversationTranscript` (the inspector's read-only conversation view) keeps its own `ScrollViewReader`; it has no composer, keyboard or streaming.
- PLAN.md: Decisions lines on the sentinel (66), the bar re-pin (last sentence of 88), "Keyboard and scrolling" (157, keeping the persona pill sentence) and #103's bar animation rule (160, which names `JumpToLatest`) give way to one line for this design; lines 59 and 62 stop contradicting line 27 (no bottom edge effect; the fill dims what scrolls under the field).

## Surfaces and directions

- **Bot chat, iPhone (`ChatScreen`, opened from the list, a push tap or search; also inside the mention peek's large detent):** opens at the latest message, cold (empty, then history arrives) or cached (`ChatSessions` already holds it), with no visible scroll animation.
- **Mac main window chat column and the separate chat window (`BotChatWindow`):** the same container; live resize with the inspector attached keeps the transcript at the bottom and the arrow hidden when the reader was at the bottom (#145).
- **Group rooms (`GroupChatScreen`):** same container; the welcome empty state shows with no arrow (render, no test).
- **Sender:** Send, Steer and Queue scroll to the bottom first, so the new bubble (or the outlined Waiting or Queued bubble) sits right above the composer, keyboard up or down, then the reply streams in below it and stays pinned.
- **Receiver (replies back):** a reply streaming, a work log growing, a turn from another client or a bot-to-bot notice, and the post-turn history reload that adopts server ids keep the latest row in place while the reader is at the bottom.
- **Reader scrolled up:** none of the above moves what they are reading; the arrow shows. A send still brings them to the bottom, like Messages.
- **Keyboard:** raising or lowering it while at the bottom keeps the latest row right above the composer; while scrolled up it leaves the reading position alone and the arrow stays usable above the bar.
- **Composer bar grows (multi-line draft, attachment tray, mention picker, dictation, offline line, approval, question, payment, offer or notice card, up to `HeightCap`):** at the bottom the latest row stays above the bar.
- **Search hit (`SearchFocus`):** the matched turn scrolls into view near the centre and is tinted for 2 s, even 500 rows up.
- **Work log or reply expanded mid-transcript:** it grows downward from the tapped header. At the very end the transcript keeps following the end instead (the same hold that follows a streaming reply), so a long log opened there pushes its header up.
- **Bot list (preview, time, status, unread), push, inspector:** untouched; no model, request or network change.
- **Light and dark:** the arrow keeps its glass look; no other visual change.

## States

- Empty chat: empty state (or room welcome), no arrow.
- Long chat (500 rows, long Markdown replies, code blocks, A2UI cards): opens at the bottom, scrolls without hitches, Jump to Latest lands at the end from the top in one tap.
- A reply taller than the screen streaming at the bottom: the end of the text stays above the composer.
- Mid-stream jump: lands at the bottom and stays pinned as the reply grows.
- Offline and error turns: unchanged; the arrow and jumps still work offline.
- Mac window resizes keep the end (`ComposerResizeTests`); rotation and iPad split view take the same container-size path but have no test of their own.
- VoiceOver: the arrow reads "Jump to Latest". Reduce Motion: the jump is not animated (code path only, no test).

## Tests

Host unit tests (macOS):

- `ReplyParseTests` (#151): redrawing the six recorded long replies 20 times takes under a quarter of parsing them 20 times, for the blocks and for the Mac segments; fails with the cache bypassed.
- `TranscriptScrollTests` (the real `TranscriptScroll`, 300 rows of mixed height, a `safeAreaBar`): cold open at the end; at the end a growing last row, an appended row and a growing or shrinking bar keep the end in view; scrolled up, growth, appends and an expansion inside the viewport move the reading position by under 1 pt; scrolled back down by hand, an appended row stays in view; the animated edge jump from 20 000 pt up lands at the end, hands over to the held end and follows streaming and appends; a search jump into rows that arrive in the same update brings the row into view.
- `ComposerResizeTests` hosts `TranscriptScroll` instead of its copy and gains #145's check: through the resize steps with the inspector attached (main window and chat window, empty and seven-line draft) the transcript never leaves the end by 40 pt (the arrow's threshold) and is at the end at rest. Fails on the v0.1.29 composition: 707 pt from the end at rest in the main window, 16 to 32 pt in the chat window.

UI tests (iOS), `ChatTranscriptUITests`, on `composer-line` loading the recorded long replies after the chat appears, and on `chat-question`:

- Opens with the latest reply right above the composer; keyboard up; Jump to Latest from far up with the keyboard up; keyboard down. v0.1.29: the jump fails and the arrow stays (#107).
- Send from far up with the keyboard up: the new reply sits right above the composer. v0.1.29: fails intermittently (#123); the rebuild before the edge hand-over sent into a blank transcript.
- A reply from another client while scrolled up: the row being read moves by under 1 pt, an expanded "Worked for" header stays put, and the arrow then lands on the reply.
- A reply after scrolling back down by hand ends right above the composer (4 of 4 runs).
- A question card in the bar (`chat-question`): the running turn stays above the card and no arrow shows. v0.1.29: fails.
- `ChatInspectorUITests` and `InAppBrowserUITests` (`layout` snapshot) failed on an earlier cut of the rebuild until the first-size hold (blank cached open); the whole suite (15 tests) passes.
- `TranscriptScrollTests.aSearchJumpFromTheEndStaysWhereItLanded` (host) covers search hits and fixture targets from the end; it fails on the cut without the "no target held" check (the reviewer's blocking finding: `chat-history` rendered at the end instead of its first turn).

Known and not fixed here: one longer iOS scenario (expand a header while scrolled up, jump to the end, scroll up, scroll back with a rubber-band bounce and a slow drag, then a reply streams in) leaves the transcript blank in about half the runs, on this branch and on its earlier green cut alike; the logs show the holds firing and then no further layout of the scroll content. Every step on its own passes in the tests above. Filed as #153 with the logs.

Lag, same simulator session, `XCTCPUMetric` of the app over the same scripted flicks and a streamed reply on the long fixture (the simulator reports no hitch ratios): v0.1.29 3.38 s CPU for the scroll script, the parse cache 3.45 s, both pull requests 3.44 s; streaming 0.45 s on both. The end-to-end difference is within noise on the simulator, so the parse cache is proven on the host only; device profiling remains the way to confirm the iPhone lag.

Renders (iPhone, light and dark): `docs/flows/renders/chat-transcript-*.png`.
