# Rooms: Reply into a message's thread (#301)

Since #300 every room send opens its own thread, so a follow-up to one member's answer goes to whoever routing picks and that member's prompt no longer holds the answer. Hermes Desktop continues a thread with Reply. Crew gets the same: Reply on a message sends the next message into that message's thread, addressed to its author.

## What Hermes has (v0.23.1, the server's version; Desktop `apps/desktop/src/plugins/hermes-bots/`, gateway `gateway/hosted_room_*.py`)

- **Desktop's Reply** (`canonical-group-history.tsx` `ReplyAction`, `canonical-group-workspace.tsx` `replyTo`): offered on a message with text that has a member author or a `thread_id`. It stores `{name, quote, thread}`, where the quote is the first non-empty trimmed line and the thread is the message's `payload.thread_id`, and prefixes the draft with `@<member handle> ` unless the draft already starts with it (no prefix for your own message or a scheduled post). A "Replying to {name}" chip with the quote and a "Cancel reply" button sits above the composer. Cancel drops the thread and keeps the draft text. Send uses `thread_id = reply.thread`; a delivered send clears the chip and the draft. The transcript draws nothing to mark a reply.
- **The log** stores only `thread_id` on `message.user` and on the member and turn events it drives. No field says which message was replied to, so nothing shown on a sent reply can come from that.
- **Routing.** Lead and Automatic route only a human message that opens a thread (`hosted_room_lead.routes_through_lead`, reused by `hosted_room_router.routed_responders`). A message in an existing thread is resolved by its mentions: an `@handle` reaches that member, and no mention reaches every member (`resolve_mentions`, `default_all`). This is in the recorded `context.log.json`: seq 10, a second message in the Lead room's thread, has no `room.assignment` and wakes both members.
- **What the member sees.** Its turn prompt holds its thread's messages since its own last turn there (`_thread_messages`, watermark per thread and member), so the replied-to message and the rest of that thread are in it.
- **Replying into a thread that is still working.** The pending discussion is the latest `message.user` per thread (`_pending_discussion`), so a reply supersedes the running discussion in that thread: its later rounds never run, and the member turn in flight publishes `turn.cancelled {reason: "superseded_by_newer_user_event"}` with no message (`plan_publication`). The reply's discussion then starts. Other threads are not affected.
- **Continue.** In 0.23.1 a `message.user` in the thread after the discussion's own message fences that discussion's Continue for good (`paused_discussion`); 0.23.0 only counted one after the pause.

## Flow

### Entry points (room transcript)

- **Context menu, iPhone and Mac.** "Reply" (`arrowshape.turn.up.left`) is the first item of the message menu, above Copy, as in Messages. On the Mac it is in both menus a message has: the SwiftUI menu on the bubble ring and `ReplyTextView`'s right-click menu on the text. Only rooms pass a reply action, so Bot Chats are unchanged.
- **Which messages.** Logged room messages that have text and a `thread_id`: member answers, your own messages, and routine posts (the output under the owner's name). No Reply on unsent or "Not sent" bubbles (not in the room yet), notices (assignments, renames, settings, "Routine: …"), error and Stopped rows, the paused row, the working row, cards or approvals. A message without a `thread_id` offers none (0.23 always logs one).
- **No swipe in this change.** Messages also replies on a rightward swipe, but in Crew the transcript-wide drag owns horizontal travel (the locked "Timestamp swipe" line: rightward travel ignored), the left screen edge is the iPhone back swipe, and the Mac has its own `TrackpadSwipe` monitor. Swipe-to-reply is a follow-up issue; the menu covers both platforms.
- **VoiceOver.** Each replyable message gets a named accessibility action "Reply", so it is in the Actions rotor without opening the menu.

### Choosing Reply

- The composer gets focus (iPhone keyboard up, Mac field focused), as Messages does.
- A reply chip shows directly above the composer: a glass capsule like the pinned-card chip (same height: 36 pt iPhone, 30 pt Mac; same leading margin), with a secondary `arrowshape.turn.up.left`, "Replying to Ada" (subheadline, medium) and the quote (subheadline, secondary), one line, then an `xmark` Cancel Reply button. The capsule hugs its content up to the composer's width; the quote truncates at the tail first, the name only when there is no room for the quote.
- **Name.** A member: its roster title (the name shown above its answer). Your own message: "You" ("Replying to You", like Desktop). A routine post: the routine's title.
- **Quote.** The first non-empty line of the message's plain text: markdown dropped, code blocks and cards skipped (`markdownBlocks`, as Speak does). A message that is only a card or code shows the name alone. `@handle` tokens show as typed.
- **Draft.** Replying to a member adds `@<handle> ` at the start of the draft unless the draft already starts with that handle, so the sent bubble starts with that member's mention capsule and the server addresses only that member. Your own message and routine posts add nothing (the reply reaches every member, as in Desktop). Text already typed stays after the handle.
- **Stacking.** Bottom bar order, top to bottom: request card (approval), reply chip, composer. While a reply is set the pinned-card chip hides (one chip above the composer at a time, as it hides for a request card); it comes back after send or cancel.
- **Tap on the chip** scrolls to the replied message and highlights it, like the pinned chip's jump to its card. If the message is not in the transcript (an older page not loaded) the tap does nothing. VoiceOver reads the chip as "Replying to Ada, <quote>", hint "Shows the message".

### Changing or cancelling

- **Reply on another message** replaces the chip. If the draft still starts with the previous target's `@handle `, that handle is swapped for the new one (or removed when the new target is your own message or a routine).
- **Cancel** (the `xmark`, the chip's "Cancel Reply" accessibility action, or Escape in the Mac composer, as in Messages) removes the chip; the draft text, including the `@handle`, stays, like Desktop. A send then opens a new thread.
- **Lifetime.** The reply belongs to the room's draft: it is kept in `ChatDrafts` in memory only, like attachments, so it survives leaving the room and coming back within a run, and is gone after relaunch (the draft text stays) and on Sign Out. Removing the `@handle` from the text keeps the reply; the thread is what makes it a reply.

### Sending

- Send uses `thread_id` = the replied message's `thread_id` and a fresh `event_id` (`GroupSession.sendParams`), then clears the chip with the draft. The bubble appears as any send does (chronological, at the end); there is no quote or connector in the transcript, because the log does not say which message was replied to, so such a marker would vanish on reload and never show for Desktop's replies.
- **Who answers.** With the `@handle`, that member, whatever the room's Who Answers setting, since a reply is never routed. Without one, every member. Its prompt holds the thread since its last turn there.
- **Reply into a thread that is still working.** Allowed, as in Desktop. The member turn in flight ends as a row under its name reading "Stopped for your newer message" (`turn.cancelled` with reason `superseded_by_newer_user_event`; other cancellations keep "Stopped"), then the reply's discussion starts. Working, Stop and approvals stay room-wide.
- **Paused thread.** A reply into a paused discussion's thread retires its Continue button (the server fences it); the reply starts a fresh discussion with a full budget. Crew's rule moves to 0.23.1's: any `message.user` in that thread after the discussion's own message, not only after the pause.
- **Failure and offline.** As every room send: the bubble stays with "Not sent: <error>" and the chip is gone. While offline the menu still offers Reply; the offline line under the composer already explains, and Send fails into "Not sent" as today.

### The reply arriving

- The addressed member's answer lands as a normal member turn (avatar and name above it) at the end of the stream, in the same thread. Replying to that answer continues the same thread again (a reply to a reply), addressed to whoever wrote it.

### Surfaces not touched

- Bot list: room rows have no preview, unread or status today; the "Draft:" line is unchanged. Push: rooms have none. Room inspector: the Who Answers footer stays ("@mentions always reach the members you name" covers a reply's handle); room-context.md's "Why" line notes that replies are never routed. Bot Chats: no Reply.
- Light and dark: system materials and styles only (glass capsule, `.secondary`).
- Long content: a long name or quote truncates on one line; the chip never wraps or grows the bar.

## Decisions to record (PLAN.md)

- "Group threads": Reply is in Crew (this spec), replacing "Desktop's Reply into a thread is not in Crew yet".
- A new line "Room Reply (#301)": entry points, the chip above the composer (the @-mentions line's "no chip row shows anywhere" is about mentions, not this), the draft prefix, memory-only lifetime, no transcript marker, swipe deferred.
- room-continue.md and room-context.md lines that say Reply is Desktop-only are updated; the Continue rule moves to 0.23.1's fence.

## Evidence and tests

- `Tests/chat_probe/run.sh room-reply` on `crew-test` plus a throwaway `crew-test-*` bot, Lead routing: an unaddressed send (the lead routes it), then a reply to the peer's answer through `GroupSession` with that answer's thread; asserts no `room.assignment` for the reply and that only the peer answers it, in the same thread. Then a reply while the thread works, to record the superseded `turn.cancelled`. Writes `Tests/fixtures/rooms/reply.log.json`, disbands the room and deletes the throwaway bot.
- `GroupSessionTests` replay the recorded logs: which turns offer Reply (member, own, routine; not notices, errors, unsent); the reply target (thread, handle, name, quote) for each; `sendParams` with a reply; the draft prefix, swap and no-duplicate rules; "Stopped for your newer message" only for the superseded reason; Continue gone after a reply sent before the pause. Each shown failing without the change.
- `./build.sh` with zero warnings, the unit suite with a timeout, `scripts/lint-ui.sh`.
- Renders: a new `group-chat-reply` snapshot (chip above the composer, a long quote truncated) on one private iPhone simulator, light and dark. Mac renders come out blank while the Mac is locked; the PR says so. The Mac right-click menu is covered by a unit test on `ReplyTextView`'s menu items (a real menu popup would drive the screen).
