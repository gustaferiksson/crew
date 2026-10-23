# Return in the composer never leaves the field

Issue #144. On the Mac, Return in the composer could hang the app at 100% CPU (v0.1.28, a long Bot Chat with Marlow: the user bubble appeared, the bot went to Working, then the app stopped responding and never recovered).

## Cause

The composer's `onKeyPress(.return, phases: .down)` sends when there is something to send and returns `.ignored` otherwise. An ignored Return, and every key repeat of a held Return (phase `.repeat`, which the handler does not receive), falls through to SwiftUI's field editor as `insertNewline:`. For a field editor that is "end editing": `-[NSTextView _giveUpFirstResponder:]` rebuilds the window's key view loop when it is stale (`recalculateKeyViewLoop`, SwiftUI's `FocusBridge` walking every nested hosting view), then makes the window first responder, and SwiftUI focuses the field again. The hang report's main thread is exactly this path. A send always leaves the loop stale (bubble added, Send button gone, Stop button shown), so a held Return, or a second Return on the now empty field, rebuilds it on a long transcript. In a unit harness the rebuild stays in milliseconds; the runaway cost in the user's window was not reproduced, so the fix removes the trigger.

The same fall-through also briefly drops and restores focus on every Return on an empty composer, which is one source of the focus flicker in #99.

## Rule

On the Mac, Return in the composer is always the composer's own, as in Messages:

- Return with text or attachments, online: sends (steers while the bot runs, where steering exists), as today. A held Return sends once: key repeats never send.
- Return with nothing to send (empty or whitespace only), or offline with text or attachments: nothing happens. No beep, no new line, the caret and focus stay, the draft is unchanged.
- Return while an input method has text in progress (Japanese, Chinese or Korean input, the accent popover) goes to the input method, which commits the text as usual, and does not send. Before this fix such a Return sent the draft without the text being composed.
- Shift+Return inserts a new line at the caret, as today.
- Not changed: Option+Return, Cmd+Return and Ctrl+Return send like Return; Tab and Shift+Tab move focus; Escape.

## Surfaces and states

- Composer in the main window's Bot Chat and group chat, and in a Bot Chat window (Mac), light and dark: no visual change.
- @-mention picker open: Return with text still sends and does not pick a suggestion (PLAN.md); Return on an empty field does nothing.
- Running: Return with text steers or sends as before; Return on empty does nothing (Stop stays a button).
- Offline: the field shows the offline reason as today; Return does nothing and the draft stays for when the connection returns.
- Dictation: the field is hidden while listening or transcribing, so Return does not reach it.
- Long content: a long draft or a long transcript behaves the same; Return never rebuilds the key view loop.
- Transcript, bot list row (preview, time, status, unread), push, inspector: unchanged; a Return that sends nothing changes nothing.
- iPhone and iPad: unchanged. A hardware-keyboard Return with nothing to send still goes to the text field, which never hangs there; key repeats now reach the handler but never send, which is what happened before (they skipped it).

## Out of scope

- The question card's answer field (`RequestCards`) and the inspector's `onSubmit` fields still let Return reach their field editor; follow-up if they show the same symptom.
- Tab and Shift+Tab still rebuild the key view loop by design (they move focus).
- Option+Return for a new line (Messages on the Mac) instead of sending: possible follow-up.

## Verification

- `ComposerReturnTests` (Mac unit, offscreen window like `ComposerCaretTests`, never key): with the composer focused, type and press Return, then a key repeat of Return, then Return on the empty field, then Return offline with text, then a held Shift+Return. Asserts after each step that the window's first responder never changed and nothing more was sent, and at the end that the key view loop was never rebuilt and the offline draft is kept. A second test presses Return with marked text in the field and asserts no send and the text committed. Before the fix every step after the first fails (the held Return, the empty Return, the offline Return and the held Shift+Return each hand the field editor `insertNewline:`, 4 rebuilds) and the marked-text Return sends the draft.
- The new line that Shift+Return inserts is not asserted in the unit test (AppKit's `sendAction(to: nil)` needs a key window); its own behaviour is unchanged and covered as before by `ComposerCaretUITests` (Mac UI, CI).
- iPhone and iPad are unchanged; hardware Return is not reachable from the iOS simulator's XCUITest (see `composer-drafts-and-sends.md`).
- No server contract change and the send path is unchanged, so no new real-server probe.
