# The composer stays put while the window resizes (#103)

Superseded for scrolling by `docs/flows/chat-transcript.md` (#150): `JumpToLatest`, the sentinel pins and `ScrollViewReader` described below are gone.

On the Mac, live-resizing a chat window with the inspector closed made the composer slide in from far away on every drag step instead of staying on the window's bottom edge.

## Cause

Measured headless (an offscreen `NSWindow` hosting `NavigationSplitView` + `NavigationStack` + a closed `.inspector`, with the real `Composer` in a `safeAreaBar` under a bottom-anchored transcript, resized in 9 to 12 pt steps, the field's window frame read on every run-loop tick):

- With `.inspector` attached, every resize step makes SwiftUI lay the chat column out at probe heights (about 1043, 148 and 96 pt) inside one transaction before the real size. Each probe placement fires the transcript's `onScrollGeometryChange`, so `isAtBottom` flips within the step. Once the transcript has been pinned by id (`proxy.scrollTo(bottomID)`, which `ChatView` does on load, on send and on every transcript change at the bottom), the last callback of each step comes from a probe, so `isAtBottom` ends every step with a different value than it started with.
- The bar carries `.animation(.smooth, value: isAtBottom)` (meant for the Jump to Latest arrow), so every flip animates the whole bar, the composer included, from the probe position to the real one. The field's bottom sat 425, 808 and 1015 pt off its resting place right after successive steps and was still 100 to 600 pt off 50 ms later.
- Without the inspector there are no probes and the field never moves; with the animation removed it never moves either, even with the inspector. `HeightCap` and its `barRoom` measurement and the field's line count are not involved (identical traces with and without them; a seven-line draft drifts the same way). The id pin only matters as the precondition above.

The inspector stays attached while closed (PLAN.md: its toolbar item and kept-alive content), so the fix is Crew's: nothing in the bar may animate on scroll state.

## The change

- The Jump to Latest arrow moves into its own modifier, `JumpToLatest` (`Sources/Chat/JumpToLatest.swift`), which owns the arrow's `.animation(.smooth, value:)` on a zero-height container around the arrow only. The bar no longer animates when `isAtBottom` changes; the arrow still scales and fades in and out exactly as before.
- Unchanged: the arrow hangs 12 pt above the top of the bar, including any card in it (locked value): `ChatView` applies `JumpToLatest` where the overlay was, outside `HeightCap` and the card stack, and the zero-height `ZStack` sits at the overlay's top like the button's own zero-height frame did. Also unchanged: `.controlSize(.large)` on macOS, its action, the bar's `.animation(.smooth, value: request?.id)` for cards arriving and leaving, `HeightCap`, the composer.
- No locked UI value changes.

## Surfaces and directions

- **Main window, Mac (sidebar, chat, inspector closed):** live resize in any direction keeps the composer on the bottom edge every frame; the transcript and the arrow behave as before.
- **Main window, inspector open:** same rule; resizing is limited by #10 as today (not measured separately: the window can't go below about 1240 pt wide there).
- **Separate chat window (`BotChatWindow`, `NavigationStack` with its own `.inspector`):** measured too: the composer drifted 8 to 9 pt per step before the fix and stays put after it.
- **Group rooms:** `GroupChatScreen` reuses `ChatView`, so the same.
- **iPhone and iPad:** the arrow still animates in and out; scrolling away and back no longer animates the bar's layout along with it, which nothing relied on. The keyboard raising the bar is unaffected: its pin keys on the inset growing while the previous distance was under 40 pt, not on the animation. Rotation and iPad window resizing get the same stability.
- **Cards in the bar (approval, question, payment, offer, notice):** they still animate in and out on `request?.id`; a card up during a resize stays put like the composer.
- **Bot list, push, inspector content, sender and receiver:** untouched; nothing here touches requests, state or the network.
- **Light and dark:** no visual change.

## Known and left for a follow-up

The probe layouts still reach `isAtBottom` itself, which this change does not alter: during a Mac resize with the inspector attached the Jump to Latest arrow can fade in and out per step, `isAtBottom` can read false right after a resize while the transcript sits at the bottom, and a transcript change landing then skips its bottom pin (the `onChange(of: transcript)` and blocks pins read `isAtBottom`). That needs a different fix (where the at-bottom state comes from), so it is filed as #145 instead of widening this one.

## States

- Empty chat, long transcript, at bottom or scrolled up: the composer never moves during a resize; the arrow shows only while scrolled up, as before.
- Multi-line draft, attachment tray, mention picker, dictation, offline line: the bar grows and shrinks with its content as before, without animating on scroll state.
- Error and offline: unchanged.

## Tests

- Unit (`ComposerResizeTests`, macOS, unhosted; adds `Sources/Chat/JumpToLatest.swift` to the CrewTests sources): the harness above, with the transcript's bottom rule and id pin copied from `ChatView` and the bar built from the real `Composer` and `JumpToLatest`, shrinks and then grows the window in steps and asserts that the field's window frame equals its resting frame on every run-loop tick. Runs for the main window (split view plus closed inspector) and the chat window (stack plus closed inspector), each with an empty and a seven-line draft. Shown failing on the refactor commit, where `JumpToLatest` still applies the animation to the whole bar (main window about 400 pt off, chat window 8 to 9 pt), and passing with the fix.
- Limit: `ChatView` itself can't compile into CrewTests (its `UserBubble` to `MentionPeek` to `Snapshot` chain pulls in the whole app), so the test guards `JumpToLatest` and the composition it copies, not a future edit that animates `ChatView`'s bar on scroll state again. The PLAN.md Decisions line states the rule for that.
- Cards in the bar are not in the harness (they live in `ChatView`); they ride the same bar and the same fix.
- The arrow's appear and disappear stay covered by `ChatSendScrollUITests` (iOS, after merge). No new UI test; no render, since nothing looks different at rest.
