# Unread after a Bot Chat's count drops in place

Issue #52. Crew's read marker (`ui_meta.crew = {session, messages}`) orders by session id then `message_count`, and assumed the count only grows within a session. It doesn't: Hermes 0.22.2 lowers `sessions.message_count` under the same id on several production paths:

- in-place compaction, mid-turn, on by default (`compression.in_place`): `archive_and_compact` sets the count to the compacted set (`hermes_state_messages.py:984-1070`);
- `/retry` (`gateway/session_transcript.py:540-570`), edit and undo (`rewind_to_message`, `hermes_state_messages.py:1834-1871`), `replace_messages` (`:816-858`);
- `clear_messages` (`:1952`) has no production caller; the recorded `Tests/fixtures/scenarios/cleared-bot-chat` (marker 17, count 2) came from rows deleted by hand on the server (PR #49).

After any of these, the marker stayed above the count: no unread until the chat grew past the old count, and `markSeen` and the writer refused to move the marker back. `crew-test` itself was in that state (marker 63, count 39).

## Rule

- A drop is never unread by itself. A marker in the canonical `resolved_id` with more messages than `message_count` reads as read at the current count (`Bot.lastRead = min(marker, position)`). A compaction tip with a later id sorts after the marker, so `min` leaves it alone.
- On seeing a drop, Crew rewrites the marker to the current count at once (the usual writer, one `profiles.configure` per 2 s, revision checked, no read push). Every device agrees, and a chat that regrows to the old count can't read as read. This is the one exception to "the marker only moves forward".
- The writer sends a target only when it is not past the bot's current position, differs from the stored marker and is not behind `lastRead`. A write from before the drop (say 18) that hits a conflict is not resent over the rebaselined marker.
- The in-memory baselines follow the same rule: the "seen" overlay is dropped once it is ahead of the position, and the first-seen baseline of a bot with no marker is clamped to the position.
- Every row added after Crew saw the lower count is unread until viewed, as any reply is.

Per path:

- Compaction mid-turn: read (Working while the turn runs); the turn's reply is unread unless the chat is open.
- Undo alone: read. Retry or edit: the replacement reply is a new message, unread unless the chat is open (as a reply to a prompt sent from another client is today).
- Clear seen empty (count 0) or after the prompt: the reply is unread.
- Known miss: a clear and its reply landing between two rosters Crew reads (app closed, iPhone in the background) read as read; the next reply is unread. The roster has no per-message id or timestamp that only grows (`last_active` is a heartbeat), so Crew can't tell that from a compaction plus a reply. Rejected: a read timestamp in the marker compared with the preview window's last row. Legacy markers have none, a displayed compaction summary row carries a fresh timestamp (false unread, the thing this fix must avoid), and it needs device-versus-server clock handling for a path with no production caller.

## Surfaces and states

- Bot list row, iPhone and Mac, light and dark: after a drop, no dot; after the next reply, unread dot and bold, ranked with unread bots; after viewing, the dot clears. Favourite tiles show the same status.
- Preview and time: refetched when the position changes (`previewPositions`), unchanged. `clearedBotChatIsTheSameSessionWithOnlyItsNewRows` still expects idle with the post-clear reply as preview and time.
- Chat open: `ChatScreen` calls `markSeen` on every position change, so new rows are read at once.
- Chat not open: the dot shows on the next reply; selecting the bot marks it read.
- Other device: the rebaselined marker reaches it within one poll, so it shows the same.
- Read push and badge: the rebaseline sends none; viewing an unread bot sends the usual read push, which clears delivered notifications and the badge elsewhere.
- Push: crew-push never reads `ui_meta.crew`; no plugin change.
- Local fallback notifications (push off): only the idle to unread transition on a new reply posts "Replied"; a drop posts nothing.
- Inspector: unaffected.
- Empty (count 0): no dot, the row shows what any empty Bot Chat shows. Offline: the cached roster holds the raw marker, `lastRead` is derived on each read, so it behaves the same. Error: a refused write keeps the overlay and retries on the next roster. Long content: n/a.

## Verification

- `ClearedBotChatScenarioTests` replays the recorded `untitled-bot-chat` then `cleared-bot-chat` rosters, with counts and markers derived from them for compaction (17 to 5 while working), retry (17 to 15, then 17), a clear seen empty, a bot with no marker and a compaction tip: no unread from any drop, unread on the next reply, the writer guard.
- Real server on `crew-test`, no bot prompt: a probe raises the marker above the count; a live `BotStore` stays idle, rewrites the marker to the current count by itself and sends no read push; then the original marker is restored.
