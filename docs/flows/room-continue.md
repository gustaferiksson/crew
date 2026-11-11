# Rooms: Continue a paused discussion, member activity, exact Retry (#269)

Hermes 0.23.0 stops a room discussion at its cap and waits for a client to continue it. Crew ignored the pause, so a capped room just went quiet. This spec adds an inline system row with Continue, puts the working member and its tool on the working row, says why a room could not wake its members, and sends the exact attempt with Retry.

## What the server has (Hermes v0.23.0 source)

- **The cap.** Each user message opens a discussion. Round 0 is everyone the message addresses; later rounds are only members another bot @-cited and who have not answered since. The driver stops at `max_rounds` (default 3, a round 2 that still produced a message) or `max_messages` (default 10 member messages) and logs `room.activity {status: "bounded", reason_code: "max_rounds" | "max_messages", thread_id, discussion_event_id}` (`gateway/hosted_room_discussion.py`). `status: "settled"` is the normal end and stays silent.
- **Continue.** `groups.continue {room_id, discussion_event_id}` grants one more full budget and logs `room.continued {discussion_event_id, thread_id, grant}`; the whole room picks the discussion back up. The server refuses ("This discussion is not paused.") unless the bounded event is the discussion's latest outcome, no `room.stop_requested` came after the discussion's own message, no newer `message.user` in its thread came after the cap, and fewer than `max_continues` (5) Continues were used (`gateway/hosted_room_router.py` `paused_discussion`, `tui_gateway/hosted_room_service.py` `continue_room`). `driver_status.max_continues` is absent on gateways without Continue.
- **Member activity.** `driver_status.member_activity` lists live tasks: `member_id`, `status` (`queued`, `running`, `stopping`), `thread_id`, `started_at` (epoch seconds), and `tool` / `progress_at` only from the process running the turn. `working` is true exactly while this list is non-empty.
- **Wake-up errors.** After 3 failed preparations the room logs one `member.unavailable` ("Members could not be woken: …"), `driver_status.last_error` holds the raw error, and `pending_actions` gets `{kind: "retry", task_id: "prepare:<room_id>", member_id: "<handles, comma-joined>", execution_generation: 1}`. Retry with that row prepares once more.
- **Retry fields.** `groups.retry` takes `task_id`, `member_id`, `execution_generation`. The gateway-owned room service refuses a Retry without the last two (`invalid_params`, `gateway/session_group_controls.py`); the legacy path matches them when present.

## Flow

### The paused row (room transcript, iPhone and Mac)

- A `bounded` event becomes a centred system row where it lands in the room, in the transcript's notice style (caption, secondary, like "Renamed to …"): "Paused after 4 messages", where the count is the member messages of that discussion logged before the pause (inflected, "1 message").
- Under the text, while Continue can still act, a tinted borderless **Continue** button, centred, footnote semibold, with a 44 pt hit area (the room's other inline action, Retry, is borderless tinted text too; a bordered capsule is heavier than the transcript's notices). VoiceOver reads "Continue Discussion". One tap sends `groups.continue` with the row's `discussion_event_id`. This mirrors Messages' inline system notices that carry one action.
- The count is every member message of the discussion before that pause, so it runs on across Continues ("Paused after 12 messages" the second time); a pause always follows at least one message.
- Continue shows only when all of these hold, the same rules the server checks, computed over the whole log:
  - this pause is the discussion's latest `room.activity` or `room.continued`;
  - no `room.stop_requested` after the discussion's own message;
  - no newer `message.user` in the same thread (Crew opens a new thread per send, so only Hermes Desktop's Reply retires a pause this way);
  - fewer `room.continued` for this discussion than `driver_status.max_continues`;
  - `max_continues` is present (older gateways get the plain row).
- While the call runs the button is gone (a second tap would be refused; the call is one round trip, and the "Continued" notice replaces it). On success the room refreshes: `room.continued` shows as a centred "Continued" notice under the paused row, the working row appears and the members carry on (the server's `working` is already true, probed). If the server could not prepare the members, the wake-up row below shows instead. On failure the room's "Something Went Wrong" alert says "This discussion can't be continued anymore." for a server refusal (the transport error otherwise) and the room refreshes, so the button comes back only if the server still shows the pause (0.23.0's gateway-owned path answers a refused Continue with a bare `invalid_params`, probed).
- **Superseded:** a new message in the thread, a Stop, or Continue elsewhere (Hermes Desktop on the same room): the row keeps its text and loses the button. A later pause of the same discussion gets its own row.
- **Used up:** after 5 Continues the sixth pause shows the text only. Sending a new message starts a new discussion.
- **Offline:** the button stays; a tap fails into the alert like Retry today. The offline banner already explains.
- **Composer:** unchanged. A send while paused is a plain `groups.send` that opens its own thread and discussion, so the user can always just keep talking; the pause keeps its Continue.

### The working row

- While the room works, the existing live work-log row ("Working for 7s" with dots, and iOS Stop) starts its timer at the running member's `started_at` (0.23.0 runs one member at a time, so the timer restarts at each hand-off, as it does today), and its footnote line (`ChatView`'s `activity`, the line Bot Chats use for "Preparing …") reads "Scout · terminal": each running or stopping member's roster title, plus its current tool when Hermes reports one, comma-separated if several ever run. Queued members are not listed. Names come from the room roster's display name, like the approval card's requester. The footnote is one line and truncates at the tail, so a long MCP tool name is cut, never the member's name first.
- Working stays room-wide (PLAN.md), so the footnote can name a member answering an earlier message; the name says who it is.
- No running rows (older gateway, a just-admitted `queued` task, a task between frames): the row behaves as today, timer from the last event, no footnote.
- The tool name is shown as Hermes reports it, with underscores as spaces (like "Preparing web search" in Bot Chats).

### Wake-up error

- The `prepare:<room_id>` retry row already renders as a stalled-task row (red triangle, Retry) because no logged event carries that task id. Its text becomes "Members couldn't be woken: <last_error>" (or "Members couldn't be woken." without one) instead of "A reply may not have finished."
- The logged `member.unavailable` event stays silent: while stalled, the state row says the same thing, with Retry; once a Retry, Send or Continue clears the stall (all three clear it server-side), the row goes away on the next refresh.
- `last_error` is at most 300 characters; the row's label wraps and Retry stays trailing, as for every room error row today.

### Retry

- Retry looks up the pending action by `task_id` and sends its `member_id` and `execution_generation` verbatim (the prepare row's `member_id` is a handle list, passed through). An action without them sends only `task_id`, as before. Probed on the 0.23.0 server: without the fields `invalid_params`, with them the request passes the check.

### Surfaces not touched

- Bot list: rooms keep their row (time from `updated_at`, which moves on the pause); no preview, unread or status for rooms, as today. Push: rooms have none. Inspector, approvals: unchanged. Bot Chats: unchanged except that `TurnView`'s notice row can carry the Continue button (only rooms set it).
- Light and dark: system styles only.
- Known limitation: rooms have no unread or status in the list, so a pause in a room that isn't open is only seen when you open it (as every room reply today).

## Evidence and tests

- `Tests/chat_probe/run.sh room-paused` on `crew-test` plus a throwaway `crew-test-*` bot: two members cite each other until the cap, records `groups.log` / `groups.state` while working, at the pause and after Continue (to the second pause) into `Tests/fixtures/rooms/`, tries a second Continue and a Continue after Stop (both refused, `invalid_params`), then disbands the room. A wake-up stall could not be produced cheaply (deleting the throwaway's profile and sending did not stall the room within 3 minutes), so the prepare row is tested on a synthesized action shaped like `hosted_room_prepare_stall.retry_action`. The same run checks `groups.retry` with and without the attempt fields.
- `GroupSessionTests` replay the recorded logs: the pause row and its count, Continue present then gone after `room.continued`, the `max_continues` limit and its absence, the working footnote and timer from `member_activity`, the prepare row text. Synthesized on top of the recorded log: a later user message or a Stop removing Continue, a tool name and several running members, and the Retry parameters.
- Renders: `group-chat-paused` (paused row) and `group-chat` (working footnote) on iPhone and Mac, light and dark.
