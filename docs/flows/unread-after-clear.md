# Unread after a Bot Chat is cleared in place

Issue #52. Hermes can empty a Bot Chat without giving it a new id (`SessionDB.clear_messages`; recorded in `Tests/fixtures/scenarios/cleared-bot-chat`: marker `{session: 20261017_091102_71c52a, messages: 17}`, server `message_count` 2, same `resolved_id`). Crew's read position orders by session id then count, so the old marker (17) stays ahead of the restarted chat: the bot never shows unread, and `markSeen` and the marker writer refuse to move the marker back, until the chat grows past 17 rows.

## Rule

- A read position in the same session as `canonical_session.resolved_id` with more messages than its `message_count` is from before a clear. Crew reads it as the start of that session (`messages: 0`): every row since the clear counts as unread until the user views the chat, the same as a reply to a prompt sent from another client. With no canonical session or no `message_count`, the marker is left as is.
- Only the same session counts. A compaction tip has a later id (and sorts after), so it never looks like a clear.
- The same applies to Crew's in-memory baselines: the "seen" overlay is dropped once it is ahead of the server's position, and the first-seen baseline of a bot with no marker is rebased to the session start.
- On detecting a cleared marker, Crew writes `{session, messages: 0}` at once through the usual writer (one `profiles.configure` per 2 s, revision checked), with no read push. So every device agrees without waiting for a view, and the restarted chat reaching the old count (17) can't read as "read" again.
- The writer writes a target only when it is not ahead of the bot's current position, differs from the stored marker and is not behind the effective one (the stored marker, or the session start when it is cleared). So a write in flight from before the clear (say 18) that hits a conflict is not resent over a newer post-clear read. The "marker only moves forward" rule gets this one exception.
- The raw server marker is kept in `bots.json`; the session-start reading is derived each time.
- Known trade-off: an undo or retry from Hermes Desktop or the CLI (Crew does neither) also drops the count. Crew then treats it as a clear: the bot shows unread and ranks with unread bots, the local "Replied" alert fires when push is off, and viewing it sends a read push, all with no new reply. A missed reply is worse than an extra dot.

## Surfaces and states

- Bot list row, iPhone and Mac, light and dark: right after a clear with no rows (count 0), no dot; after the first post-clear prompt and reply (count 2), unread dot and bold, and it ranks with unread bots; after viewing, the dot clears; the next reply (count 4) shows unread again. Favourite tiles show the same status.
- Preview and time: already refetched when the position changes (`previewPositions`), so the row shows the post-clear reply and its time (no change). `clearedBotChatIsTheSameSessionWithOnlyItsNewRows` keeps its preview and time, and its status flips from idle to unread, which is the fix.
- Cleared with no rows yet (count 0): no dot; the row shows what any empty Bot Chat shows (the server preview if any, else no preview line, time from `last_active`), unchanged, no new visual.
- Chat open while the clear and reply land: `ChatScreen` calls `markSeen` on every position change, so the reply is marked read at once and no dot shows; the open chat refetches its history on the position change (unchanged).
- Chat not open: the dot shows; selecting the bot (`BotsView` selection) marks it read.
- Other device: after one device views it, the lower marker reaches the other within its next poll, and its dot clears; the read push (`crew-push /read`) fires because the bot was unread when viewed, so the other device removes delivered notifications and zeroes the badge as for any read.
- Push: crew-push never reads `ui_meta.crew`; reply pushes after a clear already arrive. No plugin change.
- Local fallback notifications (push off): the idle to unread transition after the first post-clear reply posts the usual "Replied" alert.
- Inspector: unaffected.
- Empty: see count 0 above. Offline: the cached roster keeps the last known state; the rule is applied when it decodes, so a cached cleared marker behaves the same. Error: a failed marker write keeps the overlay (dot stays cleared locally) and retries as today. Long content: n/a.

## Verification

- Scenario tests replaying `cleared-bot-chat` after `untitled-bot-chat`: unread after the clear plus reply, cleared by `markSeen`, unread again one reply later and at the old count (positions derived from the recorded row, as `StaleExchangeScenarioTests` does), no dot at count 0, a bot with no marker, a stale pre-clear target is not written, compaction (later session id, lower count) unaffected.
- Real server on `crew-test`, no bot prompt: a probe raises the marker above the count (what Crew sees after a clear), and a live `BotStore` shows unread, writes `messages: 0` by itself, and `markSeen` then writes the current position; `profiles.list` returns the same `message_count` before and after each write. Then the original marker is restored. The clear itself has no dashboard RPC, so it is replayed, not reproduced.
