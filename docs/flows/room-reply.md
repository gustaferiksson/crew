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
- **Which messages.** Logged room messages that have text and a `thread_id`: member answers and your own messages. No Reply on unsent or "Not sent" bubbles (not in the room yet), notices (assignments, renames, settings, "Routine: …"), error and Stopped rows, the paused row, the working row, cards or approvals. A message without a `thread_id` offers none (0.23 always logs one).
- **Routine posts: not in this change.** Desktop offers Reply on them, but nothing yet shows the gateway accepts a human `message.user` on a `cron-…` thread, and a probe needs a routine run. Follow-up with that probe.
- **No swipe in this change.** Messages also replies on a rightward swipe, but in Crew the transcript-wide drag owns horizontal travel (the locked "Timestamp swipe" line: rightward travel ignored), the left screen edge is the iPhone back swipe, and the Mac has its own `TrackpadSwipe` monitor. Swipe-to-reply is a follow-up issue; the menu covers both platforms.
- **VoiceOver.** Each replyable message gets a named accessibility action "Reply", so it is in the Actions rotor without opening the menu.

### Choosing Reply

- The composer gets focus (iPhone keyboard up, Mac field focused), as Messages does.
- A reply chip shows directly above the composer: a glass capsule like the pinned-card chip (same height: 36 pt iPhone, 30 pt Mac; same leading margin), with a secondary `arrowshape.turn.up.left`, "Replying to Ada" (subheadline, medium) and the quote (subheadline, secondary), one line, then an `xmark` Cancel Reply button. The capsule hugs its content up to the composer's width; the quote truncates at the tail first, the name only when there is no room for the quote.
- **Name.** A member: its roster title (the name shown above its answer). Your own message: "You" ("Replying to You", like Desktop).
- **Quote.** The first non-empty line of the message's plain text: markdown dropped, code blocks and cards skipped (`markdownBlocks`, as Speak does). A message that is only a card or code shows the name alone. `@handle` tokens show as typed.
- **Draft.** Replying to a member adds `@<handle> ` (the room member's `handle`, which the server matches) at the start of the draft unless the draft already starts with it, so the server addresses only that member. In rooms Crew creates the handle is the bot's mention handle, so the sent bubble starts with that member's mention capsule; a Desktop-made room whose handle differs from the bot's shows the token as typed text. Your own message adds nothing (the reply reaches every member, as in Desktop). Text already typed stays after the handle.
- **Stacking.** Bottom bar order, top to bottom: request card (approval), reply chip, composer. While a reply is set the pinned-card chip hides (one chip above the composer at a time, as it already hides for a request card); it comes back after send or cancel. This changes the pinned card's surface, so pinned-card.md and PLAN.md's "Pinned card" line get the rule.
- VoiceOver reads the chip as "Replying to Ada, <quote>" with the Cancel Reply button after it.

### Changing or cancelling

- **Reply on another message** replaces the chip (and adds the new member's `@handle` by the same rule).
- **Cancel** (the `xmark`, or the chip's "Cancel Reply" accessibility action) removes the chip; the draft text, including the `@handle`, stays, like Desktop. A send then opens a new thread.
- **Lifetime.** The reply belongs to the room's draft: it is kept in `ChatDrafts` in memory only, like attachments, so it survives leaving the room and coming back within a run, and is gone after relaunch (the draft text stays) and on Sign Out. Removing the `@handle` from the text keeps the reply; the thread is what makes it a reply.
- **Original gone or changed.** The chip holds its own name, quote and thread, so it never reads the original again. Room logs are append-only, so a message is never deleted while its room exists. A disbanded room leaves the room list and its screen closes; its stored reply is dropped with the room's draft. The handle comes from the room's roster, which the server freezes, so renaming the bot does not break it; a reply whose handle names no member (edited by hand) addresses nobody, so the server wakes every member.

### Sending

- Send uses `thread_id` = the replied message's `thread_id` and a fresh `event_id` (`GroupSession.sendParams`), then clears the chip with the draft. The bubble appears as any send does (chronological, at the end); there is no quote or connector in the transcript, because the log does not say which message was replied to, so such a marker would vanish on reload and never show for Desktop's replies.
- **Who answers.** With the `@handle`, that member, whatever the room's Who Answers setting, since a reply is never routed. Without one (a reply to your own message, or the handle deleted), every member, even in a Lead or Automatic room. That contradicts the Lead footer ("<Name> decides who takes a message that names nobody") for replies; accepted for Desktop parity, and room-context.md says so. Its prompt holds the thread since its last turn there.
- **Reply into a thread that is still working.** Allowed, as in Desktop. Hermes drops the answer in flight: that member's turn ends as the existing Stopped row under its name (`turn.cancelled`, reason `superseded_by_newer_user_event`), then the reply's discussion starts. Working, Stop and approvals stay room-wide. room-context.md's "Sending while the room works" gets this exception.
- **Paused thread.** A reply into a paused discussion's thread retires its Continue button (Crew's existing rule: a newer `message.user` in that thread after the pause); the reply starts a fresh discussion with a full budget.
- **Failure and offline.** As every room send: the bubble stays with "Not sent: <error>" and the chip is gone. While offline the menu still offers Reply; the offline line under the composer already explains, and Send fails into "Not sent" as today.

### The reply arriving

- The addressed member's answer lands as a normal member turn (avatar and name above it) at the end of the stream, in the same thread. Replying to that answer continues the same thread again (a reply to a reply), addressed to whoever wrote it.

### Surfaces not touched

- Bot list: room rows have no preview, unread or status today; the "Draft:" line is unchanged. Push: rooms have none. Room inspector: the Who Answers footer stays ("@mentions always reach the members you name" covers a reply's handle); room-context.md's "Why" line notes that replies are never routed. Bot Chats: no Reply.
- Light and dark: system materials and styles only (glass capsule, `.secondary`).
- Long content: a long name or quote truncates on one line; the chip never wraps or grows the bar.

### Later layers (follow-ups, not in this change)

Kept out so what ships is what was reviewed: swipe-to-reply; Reply on routine posts (after a probe); a tap on the chip that scrolls to the replied message; swapping the previous target's `@handle` when the target changes; a reason-specific label for the superseded turn ("Stopped for your newer message"); Crew's Continue rule moving to 0.23.1's stricter fence (a `message.user` in the thread after the discussion's own message, not only after the pause); Escape to cancel on the Mac (Messages' behaviour unverified, and the Mac composer's key handling is fragile per PLAN.md).

## Decisions to record (PLAN.md)

- "Group threads": Reply is in Crew (this spec), replacing "Desktop's Reply into a thread is not in Crew yet".
- A new line "Room Reply (#301)": entry points, the chip above the composer (the @-mentions line's "no chip row shows anywhere" is about mentions, not this), the draft prefix, memory-only lifetime, no transcript marker, swipe deferred.
- "Pinned card": hidden while a reply chip shows (also in pinned-card.md).
- room-continue.md's "only Hermes Desktop's Reply retires a pause" and room-context.md's "Reply … is not in Crew yet", "Sending while the room works" and Who Answers "Why" lines are updated.

## Evidence and tests

- `Tests/chat_probe/run.sh room-reply` on `crew-test` plus a throwaway `crew-test-*` bot, Lead routing: an opener addressed to the peer (`@handle`, so the answer is deterministic), then a reply to the peer's answer through `GroupSession` with that answer's thread; asserts the logged reply `message.user` and the peer's answering `message.member` both carry the opener's `thread_id`. Then a reply while the thread works, to record the superseded `turn.cancelled`. Writes `Tests/fixtures/rooms/reply.log.json`, disbands the room and deletes the throwaway bot.
- `GroupSessionTests` replay the recorded logs: which turns offer Reply (member and own; not notices, errors, routine posts, unsent); the reply target (thread, handle, name, quote) for each; `sendParams` with a reply; the draft prefix and no-duplicate rule; the superseded turn as a Stopped row. Each shown failing without the change.
- `./build.sh` with zero warnings, the unit suite with a timeout, `scripts/lint-ui.sh`.
- Renders: a new `group-chat-reply` snapshot (chip above the composer, a long quote truncated) on one private iPhone simulator, light and dark. Mac renders come out blank while the Mac is locked; the PR says so. The Mac right-click menu is covered by a unit test on `ReplyTextView`'s menu items (a real menu popup would drive the screen).
