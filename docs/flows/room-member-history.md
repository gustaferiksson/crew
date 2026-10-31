# Room member history: size and Compress (#120)

The issue asks for each member's distance to "the caps (about 200 messages and 32k characters per turn)" plus Compress per member and a near-cap warning. Probing Hermes 0.22.5 and its source shows those caps don't exist for the rooms Crew uses. What does grow, and what Compress acts on, is each member's hidden room session. This spec shows that honestly and drops the near-cap banner.

## What the server has (Hermes 0.22.5, probed on crew-test)

- **The 200-message / 32k-character caps are Desktop-only.** They are Hermes Desktop's constants for its own client-driven rooms (`GROUP_CHAT_HISTORY_LIMIT = 200`, `GROUP_CHAT_HISTORY_CHARS = 32_000`, `apps/desktop/src/plugins/hermes-bots/group-chat.ts`). Crew uses hosted rooms (`groups.*` with the driver). They cut each turn's input to the last 24 new lines of the current thread and 128 KiB (`MAX_DISCUSSION_DELTA_LINES`, `MAX_PROMPT_BYTES`; overflow reads "[Earlier content omitted to fit this turn.]"). Both are per-turn windows that reset every turn, so nothing accumulates towards them and there is no "how close to the cap" number.
- **What grows is the member's room session.** The driver keeps exactly one session per local member per room, in the member's profile: title `Group: <room_id>` whatever the thread, `source: bot_room`, hidden (`room_session_title`). Every room turn adds to it and Hermes auto-compresses it like any session. Desktop has a per-member "Compress history" button for the same reason (Hermes #102291).
- Endpoints, verified on throwaway rooms of `crew-test` plus a `crew-test-*` bot:
  - `session.list {profile, title: "Group: <room_id>", include_hidden: true}` (the driver's own lookup) returns `id`, `resolved_id` (compression tip), `message_count` and `live_message_count`. No resume needed.
  - `session.resume {profile, session_id: resolved_id ?? id, omit_messages: true}` then `session.compress {session_id: <runtime>}` returns `status`, `before_messages`/`after_messages`, `before_tokens`/`after_tokens` and `summary.headline` ("No changes from compression: 4 messages"). This is Desktop's path and the 1:1 Compact Chat call. Resume by `resolved_id` reuses the driver's live record.
  - The room keeps working afterwards: after Crew resumed and compressed crew-test's room session, disconnected for 20 s and reconnected, a new round went to the same session id (4 to 6 messages). Crew never calls `session.close` on it.
  - `session.usage` (after resume) has `context_percent` and `compressions`, but Desktop never resumes for display and Crew doesn't need it (see Decision).
- No cap or size field exists in `groups.state`, `groups.list` or `groups.capabilities`.

## Decision

Show each member's room history length and offer Compress per member, as Desktop does. No near-cap warning, because hosted rooms have no cap to be near; Hermes' own degradation signal, "Session compressed N times", already reaches the user in the member's own turns (#129). PLAN.md gets a Decisions line saying the issue's 200/32k "Done when" does not apply to hosted rooms.

## Flow

### Room inspector, Members section (Mac inspector column, iPhone pushed page)

- Each member row keeps its avatar, name and role line, and the tap that selects the bot. The size is trailing secondary text, like Settings: "128 in history" (`live_message_count ?? message_count`, system number format). The accessibility label reads "128 messages in room history".
- Compress follows the inspector's row-action convention (PLAN.md, logins, shops, routines): an iOS trailing swipe action "Compress" and a context menu item "Compress Room History…" on both platforms (the context menu covers Mac). While it runs, a small `ProgressView` replaces the count.
- Compress asks first, like Compact Chat (#115): "Compress Ada's Room History?" / "Ada replaces older room messages in its context with a summary. The room's transcript stays." Buttons Compress, Cancel.
- Then `session.resume` + `session.compress` with a 660 s timeout (Desktop's, matching the gateway's compute-host wait), then the count reloads from `session.list`.
- Outcomes:
  - `status: compressed` (or a summary headline): alert "Room History Compressed" with Hermes' headline.
  - `status: pending`, or a timeout: alert "Still Compressing" / "Hermes is finishing in the background. Check again in a minute."
  - `compressed: false` with `lock_held`, or error 4009 (busy): alert "Couldn't Compress Room History" / "Ada is busy right now. Try again when the room is quiet."
  - `status: aborted` or `summary.aborted`: the same alert title with Hermes' note.
  - Any other error: the same alert title with the server's message; the count stays.

### Data and cost

- `session.list` for each local member, in parallel (at most 6), once when the inspector appears and after each Compress. Never in the chat, never polled, nothing on the transcript or streaming path; nothing persisted.
- Working state: the inspector reads `groups.state` once alongside the counts (the chat's `GroupSession` polling may stop while the inspector is pushed on iPhone). Compress is disabled while `driver_status.working`, offline, or while another Compress runs.

### States

- 2 to 6 members; names truncate as today.
- A member with no room session yet: "No history" in secondary, no actions (Desktop's "Nothing to compress").
- Peer members (`target.kind == "peer"`, their session lives on another gateway): no count, no actions. `RoomMember` decodes `target.kind` for this.
- A member with no Crew bot (row already disabled) or whose `session.list` fails: "Unavailable", no actions.
- Room working: actions disabled; counts are from when the inspector appeared.
- Offline: counts "Unavailable", actions disabled.
- Light and dark: system styles only.
- Bot list, push, the room transcript, the member's own inspector and 1:1 Bot Chat (a different session): unchanged.
- Servers without the room driver (`groups.capabilities` gate): no rooms, nothing changes.

## Evidence and tests

- First implementation step: record a `room-member-history` scenario on `crew-test` plus a throwaway (`session.list` rows before and after a Compress that changes something, and the compress reply) into `Tests/fixtures`, then unit tests that decode them into row text and action state, each shown failing without the fix.
- Real-server probe of the full flow on crew-test, every direction: Compress, then another room round lands in the same session.
- Renders of `group-inspector` on iPhone and Mac, light and dark.
- Probe side effects so far: crew-test keeps two hidden `Group: room-…` sessions from the disbanded test rooms; the room store keeps their tombstones.
