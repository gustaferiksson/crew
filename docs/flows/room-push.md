# Room push (#111)

A room member's finished message, or its approval request, reaches the lock screen like a Messages group thread. Today crew-push pushes only Bot Chat and routines; rooms are silent until opened.

## Source (crew-push 0.8.0)

Hermes v0.23.1 has no plugin hook on the room log (`message.member` rows are written by the room driver with no observer), and `on_room_member_activity` never fires for gateway-owned rooms (their member turns publish on the member's own session, see `tui_gateway/hosted_room_member_activity.py` `record_task_progress`) and has no "finished message" kind. Every member turn, though, runs as an ordinary agent turn on the member profile's hidden room session (`source = bot_room`, title `Group: <room_id>`, `gateway/session_hosted_rpc.py`), so the hooks crew-push already uses fire for it:

- `on_session_end` (completed, not interrupted) with the reply cached by `post_llm_call`: one push per member message. The room log's text is the same `final_response`. A reply that `is_pass_text` treats as silence (`pass`, `(pass)`) is never logged, so it never pushes. Failed turns show in the room as an error row and do not push (the Bot Chat `turn_error` push is for the one chat the user drives; a room failure is not addressed to the user).
- `pre_approval_request` on that session: the room approval push, same kind, category and 5 minute expiry as a Bot Chat approval.

crew-push maps the session to its room read-only: the session row in the member's `state.db` (`source == "bot_room"`, title `Group: <room_id>`), then the room's name and the member's display name from Hermes' own `gateway.hosted_rooms.list_rooms` (read connection). A disbanded room is not listed, so a turn that finishes after Disband does not push. Room clarify never happens (Hermes disables the `clarify` toolset in rooms).

## Content (Messages group thread)

- Title: the room name. Subtitle: the member's name (roster `display_name`, else the bot title). Body: the reply through `plain()` (Markdown stripped, a card becomes its `Header` title), clipped to 400 characters like every push.
- Approval: title room name, subtitle "<member> · <description>", body the redacted command.
- Previews off (Settings > Notifications): title only plus the kind's generic body ("Replied", "Needs approval"); member and text stay hidden, as for Bot Chat.
- `thread-id` `group:<room_id>` (the app's room selection id), so Notification Center stacks a room's messages together and apart from the member's Bot Chat (`profile.<id>`).
- `apns-collapse-id` per member turn for replies, so every message stays in the room's stack as in Messages (a member's room session spans every thread and round, so the Bot Chat per-session rule would drop earlier unread messages); per member room session for approvals, like Bot Chat. No burst collapsing across members: Messages shows one banner per sender, and Hermes gives no "all members done" hook short of `turn.settled` in the log.
- Prefs: replies use the existing Replies toggle, approvals the Approvals toggle. No new category, no new toggle.
- `crew` payload adds `room_id`.

## Surfaces

- **Lock screen and banner (iPhone, Mac):** as above; time-sensitive for approvals, active for replies (same levels as Bot Chat).
- **Notification Center:** one stack per room.
- **Tap, iPhone:** opens the app on that room (`selection = group:<room_id>`), pushed as the detail like a sidebar tap. Cold launch: the selection waits for `groups.list` like a bot selection waits for the roster.
- **Tap, Mac:** brings up the main window and selects the room. A room push never opens the member bot's own chat window (routing is on the room, not the member's profile).
- **Suppression while viewing:** the app is active and the room is the visible selection (`PushCenter.visibleBot == group:<room_id>`): no banner, no sound, nothing in the list (the transcript shows it). Viewing the member's Bot Chat does not suppress room pushes.
- **Opening a room** removes that room's delivered notifications (thread `group:<room_id>`), like opening a bot.
- **Room row in the list:** rooms have no unread state today (PLAN "Group rooms"); the push is the signal. Unread dots for rooms are a follow-up.
- **Approvals in a room:** tap opens the room, where the existing approval card (once/deny, `groups.approve`) answers it. No notification action buttons, as for Bot Chat approvals. Answered elsewhere: like Bot Chat approvals (only payments send a resolved push), the notification stays until opened or until its 5 minute expiry on APNs; opening the room clears it.
- **Routines that post into a room (#349):** unchanged. The routine runs as a `cron` session and pushes as a routine into the bot's own thread under the Routines pref; its room post is not a member turn, so it does not push again.
- **Paused room (`bounded`):** no push; nothing is addressed to the user until they press Continue.
- **Muted / hidden:** a room with a hidden member still pushes (hiding is per bot, the room is not hidden). Rooms have no mute in Crew or Hermes; per-room mute is a follow-up.
- **Long content:** clipped by `clip()` (400 body, 120 subtitle); a card-only reply shows the card's title.
- **Other device reading:** opening a room on one device does not clear the other's notifications (the `read` silent push is per bot). Follow-up.
- **Offline / no push (`isPushing` false):** no local-notification fallback for rooms (the fallback reads bot statuses only). Unchanged.
- **Light/dark:** system notification UI only; no visuals in the app change.

## States

- Room disbanded mid-turn: no push. Room renamed: the next push uses the new name. Hermes refuses an empty room name, so the title is never empty.
- Tapping a stale push (room disbanded since, or a server whose `groups.capabilities` no longer gates rooms in): the selection is set; the bot roster load leaves a room selection alone (it used to clear any selection that was not a bot before `groups.list` answered, which would have dropped a cold-launch tap), and the room rule clears it once the room list changes without it. Until then the detail shows "No Bot Selected" (a server with no rooms at all never changes the list, so it stays there).
- Older crew-push: no room pushes (unchanged). Older Crew with new crew-push: the push shows, a tap selects the member bot (old `PushRoute` ignores `room_id`), viewing that bot's Bot Chat suppresses the banner, and opening the room does not clear its stack. Acceptable for one release; Crew and crew-push ship together.
- Peer rooms (member on another gateway): unverified. The turn runs on the member's gateway, whose `list_rooms` probably does not list a room owned elsewhere, so most likely nothing pushes.

## Verification

- crew-push unit tests: a room member turn (`bot_room` session titled `Group: <room_id>`, real-shaped `list_rooms` row) pushes title, subtitle, body, thread-id, collapse id and `room_id`; pass, failed, interrupted and disbanded do not; a room approval pushes. Shown failing on main.
- App unit tests (`RoomPushTests`) decode crew-push's own payload (`Tests/fixtures/rooms/push-room-reply.json`, asserted byte for byte by the crew-push test): it routes to `group:<room_id>`; presentation is suppressed only while that room is visible, not while the member's Bot Chat is; a Bot Chat route is unchanged. Clearing the `group:<room_id>` stack on open goes through `UNUserNotificationCenter` and is checked after deploy, not unit tested.
- After deploy: `GET /api/plugins/crew-push/status` shows `plugin_version` 0.8.0 and `features` containing `rooms`; a message in a `crew-test` room with the app in the background pushes one notification per replying member.
