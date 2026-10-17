# Composer: drafts, the in-field action, Stop, and what a sent message shows

Seven user reports from the iPhone, fixed together because they all live in the composer and the bubbles it produces. Judged against Messages (drafts, the send arrow in the field, delivery labels, Send Later) and the ChatGPT and Claude apps (Stop while a reply runs).

## 1. Drafts per chat

- **What:** the text in a chat's composer is that chat's unsent draft. Leaving the chat (back to the list, another bot, the mention sheet, the Mac window closing, the app quitting or being killed) keeps it; coming back puts it in the field, the keyboard down. Like Messages, nothing is saved by the user.
- **Scope:** one draft per bot (`Bot.ID`) and per group room (`Room.selectionID`). The mention sheet's live chat and the Mac's per-bot window bind to the same stored draft as the main chat of that bot, so a second visible field mirrors the typing live (one value, no overwrite race).
- **What is kept:** the text, which also restores the mention picker (it is derived from the text: `@` at the end shows it again). Attachments in the tray are kept in memory per chat, so they survive navigation but not a relaunch (an image can be 25 MB). Dictation in progress stops on leave, as today; the words already transcribed are in the text.
- **Storage:** `drafts.json` in Application Support, written atomically on each change (a few hundred bytes, so no debounce and nothing lost to a kill; dictation's live results write the same way). iOS keeps the default data protection, like `bots.json`. Never `UserDefaults` (`dev.gustaf.crew` is shared with the Mac release build). On the Mac the file sits next to `bots.json`, so a Debug and a release Mac build share drafts and a Debug sign-out clears them, the same known trade-off as the bot cache. Whitespace-only drafts are not stored.
- **Cleared:** on send (also send while running: steer and queue), on sign-out (with the bot cache), when the bot is deleted from this device. An entry for a bot or room removed elsewhere is never shown (it has no row) and goes with the next sign-out; it is not pruned on roster syncs, since an empty or partial list during a reconnect would delete real drafts.
- **Bot list row:** for every chat except the one open next to the list (Mac and iPad sidebar, like Messages on the Mac), a non-empty draft replaces the preview line with "Draft:" in red followed by the draft text flattened to one line, two lines max, like Messages and Mail (red is Apple's draft marker). An attachments-only draft reads "Draft: 1 Attachment" (or "2 Attachments"); attachments live in memory, so this shows only until a relaunch. The time label, unread dot, avatar status and Working/Waiting/Failed label are unchanged; the row does not move (the order still follows server activity). Group rows show the same in place of the member list. Search still filters on the server preview, not the draft.
- **Favourite tiles:** no change (no preview line there).
- **Mac and iPad:** the same store and row. Push: unchanged.
- **States:** offline: the field stays editable (like Messages); only Send, Steer, Queue, attach and Stop are disabled, and the offline line shows as today. Long draft: the row clamps to two lines, the field grows to six lines then scrolls. Emoji and right-to-left text are stored as typed.

## 2. Composer gone after the inspector (bug)

- **Cause (from the UI test's accessibility dump):** with the field focused, the pill pushes `BotInspector` and the keyboard stays up through the push. On pop the chat comes back with the field still focused (`Keyboard Focused`, value intact, so nothing was rebuilt) but without the keyboard's bottom inset: the composer sits at y 835 behind a keyboard that starts at y 590, and the last turn is under the keyboard.
- **Fix:** like Messages tapping the contact header, the pill dismisses the keyboard (clears the composer's focus) before pushing; coming back shows the chat with the keyboard down and the draft in place. No refocus on return (Messages does not).
- **Other pushes:** the inspector is the only push from a chat on iPhone. A back swipe cancelled halfway never leaves the chat, and sheets (mention chat, photo picker, file importer) bring their own keyboard handling.
- **Mac:** the inspector is a column, focus is not touched.

## 3. Transcript jumps when the keyboard opens (bug)

- **Report:** tapping the field in a long chat sitting at the bottom brings up the keyboard and leaves the area between header and composer almost empty; the last turns end up under the header.
- **Cause (instrumented with `onScrollGeometryChange` in a UI test):** the transcript pinned itself to the bottom through `ScrollPosition.scrollTo(edge: .bottom)`, which leaves the position in an edge state. When the keyboard raises the bar's bottom inset by 294 pt, SwiftUI re-resolves that edge on top of the inset change: the offset moved by 588 pt (1635 to 2223), twice the keyboard, so the last turn landed under the header. Without the edge state the offset moves by exactly 294 pt.
- **Fix:** every pin to the bottom scrolls to the bottom sentinel by id (`ScrollViewReader.scrollTo(bottomID, anchor: .bottom)`), which leaves no edge state behind; the existing "re-pin when the bar grows while at the bottom" rule (#33) then handles the keyboard like any other bar growth. Like Messages, the last turn stays right above the composer; a reader scrolled up stays where they were. `.scrollDismissesKeyboard(.interactively)` stays.

## 4. The composer row (iOS)

- **Side margins:** 16 pt instead of 28 pt, so `+` and the field line up with the transcript's 16 pt text padding (user request; Messages uses about 8 to 12 pt). The bottom offset (28 pt, 8 pt focused) stays.
- **Layout, like Messages:** `+` (attach) stays a separate glass circle on the left. The field is one glass capsule that spans the rest of the row at every height (fixes the field shrinking narrower once the draft wraps). The current action sits inside the capsule at the trailing edge, bottom-aligned so it stays on the last line as the field grows: a 32 pt circle in the 40 pt field (4 pt inset on the bottom and trailing edges).
- **Which action:**
  - Idle, empty: the waveform glyph (hold to dictate), as today.
  - Idle, text or attachments: blue Send circle (white arrow up).
  - Running, empty: the waveform, then a Stop circle (stop.fill) where Send will appear, like ChatGPT and Claude.
  - Running, text: the blue Send circle. A tap sends with the default (steer when the bot supports it, queue when attachments or the last turn is an agent message, as today); a long press opens Steer and Queue (`Menu(primaryAction:)`).
  - Dictating: the field shows the level waveform and timer as today, no action circle.
- **Stop while typing:** the live "Working for 24s" row in the transcript gets a small Stop button at its trailing end (a 20 pt glyph with a 44 pt hit target, VoiceOver "Stop"), tied to the run it stops, so Stop is never squeezed next to Send and is reachable while a draft exists. It shows only on the last turn while it streams, also while an approval or question card fills the bar, and is disabled offline. ChatGPT and Claude keep only Stop in the send slot until the run ends; Crew can't, because sending while running (steer, queue) is a core feature, so Send takes the slot when there is text and Stop moves to the run it belongs to. When the field is empty the in-field Stop is there too, so Stop is always one tap away at the bottom.
- **Mac:** unchanged (field, separate Stop circle, Send circle, 16 pt margins). The Mac field already fills the row, has no keyboard and is not part of the reports; it keeps its layout until it is rendered and judged on its own.
- **Locked values:** the composer height (40 pt iOS field) and bottom offset stay; the iOS side margin changes from 28 to 16 pt; a new locked line records the in-field action (32 pt circle, 4 pt inset, bottom trailing, iOS).
- **Accessibility:** Send, Stop, Steer and Dictate keep their labels; the long-press menu is also reachable as the accessibility actions "Steer" and "Queue".

## 5. Steer and queued messages are user bubbles

- **Today:** a steer shows as a small grey note between tool rows; a queued message shows nothing until it is submitted. The user cannot tell that it was sent, read, or counted as their message.
- **Wanted:** everything the user sends is a user bubble.
  - **Waiting:** a steer not yet taken by the agent, or a queued message waiting for the turn to end, is an outlined bubble (the same shape with a 1 pt stroke in the bubble blue and blue text on the chat background), like a Send Later message in Messages, with a caption under it, trailing, in the secondary style: "Waiting" for a steer, "Queued" for a queued message (like Messages' "Delivered" line). The solid bubble's locked colours are unchanged.
  - **Order:** waiting bubbles always sit last, below the running turn, whose work keeps growing above them; steers first, then queued messages, each in send order.
  - **Taken:** a steer is taken when the tool batch it rides on finishes (Hermes appends it as a user row after the batch's last tool result, then calls the model again). From the first event after that batch, the bubble turns solid, the running turn's work log closes there ("Worked for 9s") and a new run continues below the bubble, so the steer sits in the timeline where the agent read it. Several steers taken by one batch become one bubble with their texts on separate lines, as Hermes joins them into one row. A queued message turns solid when Crew submits it at the end of the turn (it becomes the next turn, as today).
  - **Not taken:** if the turn ends before another tool batch, Hermes sends the steer as the next prompt; the waiting bubble becomes that turn's bubble (no duplicate).
  - **Back to the draft, one rule:** whenever a waiting message is dropped (Stop drops waiting steers and queued messages, as Hermes drops its pending steer on interrupt; Remove from Queue; a steer the server refuses, with the error alert), its text is appended to the draft on a new line, in send order, so nothing typed is lost. A refused steer goes back to the draft rather than staying as a "Not Delivered" bubble, because Crew has no resend for steers and the draft is where the user fixes and resends.
  - **Remove from Queue:** a queued bubble's long-press menu adds "Remove from Queue" (destructive).
  - **Lifetime:** queued and waiting messages live with the open chat session, as the queue does today. A history reload while a steer waits keeps the waiting bubble until the turn that takes it arrives.
- **The answer to a steer:** the first text the bot writes after taking a steer is its answer to it. When a tool call follows that text (so it would be narration), it shows under the bubble as normal reply text (full contrast, not the dimmed narration style), then the work log continues below it and the final reply follows as usual. When that first text is the final reply, it is simply the reply, shown once. A tool call before any text means the next text is the answer. An interrupted or failed run keeps whatever answer arrived. Other narration between tools stays dimmed in the log.
- **History:** a `display_kind: steer` row splits the turn the same way (the work before it, the bubble, the answer, the rest), so a reload looks the same as live. Covered by a test that replays the recorded steer events and the matching history rows, and one recorded on `crew-test` with an answer.
- **Bot list preview:** follows the last visible turn as today (a solid steer becomes the latest user message); waiting bubbles do not change the preview. Unread: the chat is open while sending, so it stays seen as today. Push: the split turn still ends once, so crew-push sends one reply push as today.
- **Groups:** rooms have no steer or queue (sending while working is a plain `groups.send`), so nothing changes there.
- **Mac:** same bubbles and states.

## 6. User bubbles never fold

- A long user message always shows in full, like Messages: "Show more"/"Show less" and the height measuring behind it are removed from user bubbles. Replies never had it. PLAN.md's layer 3 line drops "Show more for long user messages".

## Surfaces checked

Chat (iPhone light and dark): composer empty, one line, multi-line, running empty, running with text; steer waiting and taken with its answer; queued; chat after returning from the inspector; chat with the keyboard up in a long chat. Bot list row and group row with a draft. Mac: not rendered (no Mac window driving); the Mac composer is unchanged, and the shared pieces (drafts store, steer split and answer, queued state) are covered by the unit tests below.

## Tests

- Unit (`ChatDraftsTests`, `SteerTests`): drafts store round trip through a temp file, whitespace not stored, clear; steer live replay (`chat.steer-turn` events) equals `Transcript(history:)` of the same rows; the steer answer live and from history rows; queued and waiting states, ordering and the drop rule.
- UI (iPhone simulator): draft survives back and forth and shows "Draft:" in the row, cleared on send; composer and last turn visible after the inspector round trip with the keyboard up; last turn above the composer after the keyboard opens in a long chat; multi-line draft keeps the field full width and Send works; running empty shows Stop in the field, running with text shows Send, and Stop on the Working row works; a queued bubble turns solid when submitted.
