# Rooms: purpose, shared notes, who answers, routines that post into a room (#270)

Hermes 0.23.0 gives a room settings that every member's turn prompt carries (a purpose and shared notes) and a rule for who answers a message that names nobody. Hermes Desktop edits them; Crew showed none of it, so a room whose lead hands out messages, or whose router skips members, behaved in ways Crew couldn't explain. Routines can also post into a room now (Desktop sets that up), and Crew drew such a post as the user's own bubble.

## What the server has (Hermes v0.23.0 source, probed on the server)

- **Read.** `groups.state` returns `context {purpose, notes, routing, lead_member_id}` (`gateway/hosted_room_context.py` `room_context`), absent for a disbanded room and on gateways without room settings. `routing` is `everyone` (default), `lead` or `auto`; `lead_member_id` is a member id, empty unless `routing` is `lead`. `driver_status.routing_modes` lists the modes the gateway accepts (absent on older gateways, which accept `everyone` and `lead`).
- **Write.** `groups.context {room_id, event_id, purpose, notes, routing?, lead_member_id?}` appends one `room.context_set` event and returns `{context, event}`. `purpose` and `notes` are required strings every time (an empty string clears one); omitted `routing`/`lead_member_id` keep the current values, read under the append's write lock. The same `event_id` is idempotent. There is no revision or compare-and-set: two clients saving purpose or notes at once means the last write wins.
- **Limits.** Purpose: whitespace collapsed to single spaces, at most 500 characters. Notes: trimmed, at most 4096 UTF-8 bytes. `lead` needs a `lead_member_id` that is a seated member. The 0.23.0 gateway answers every refusal (empty lead, a lead who isn't a member, 501 characters, 4098 bytes, an unknown routing, missing notes) with a bare `invalid_params` (code 4001, probed), so Crew checks the limits itself.
- **When it applies.** Purpose and notes are read as of the message that opens a discussion, so an edit applies from the next message. Routing applies only to a human message that opens a new thread and @mentions nobody (`hosted_room_lead.routes_through_lead`, reused by the router): an @mention or `@all`/`@everyone`, a scheduled post, and any message in a thread that already has a message go to the usual responders (no mention means everyone). Hermes Desktop starts a new thread for every message unless it is a Reply (`canonical-group-send.ts` `freshEntry`: `thread_id` is the send's own `event_id` unless the hover Reply passes the replied message's thread), so routing applies to every unaddressed message; Crew does the same (see "Threads" below).
- **Lead.** The lead runs a routing turn and the gateway logs `room.assignment {discussion_event_id, thread_id, task_id, lead_member_id, member_ids, fallback}`: `fallback` true means the answer named nobody (or the turn failed) and the lead takes it alone. Probed: the routing turn logs only `room.assignment` and a `turn.settled` with `passed: true` (no `message.member`), and the lead may pick itself (`member_ids: [lead]`). A second unaddressed message in the same thread went to everyone (the lead answered, the other member passed).
- **Automatic.** One model call picks; the gateway logs `room.routed {discussion_event_id, thread_id, member_ids, everyone, fallback}` before any turn (`fallback` true: the router failed, everyone answers). Probed: `working` stays false for about 2 s between the send and `room.routed`, so Crew's room would fall back to its 10 s poll right after a send.
- **Routine posts.** `cron.manage add` takes `deliver`; `room:<room_id>[@<profile>]` posts the job's output into the room as a `message.user` whose actor is `{kind: user, id: "cron:<job id>", display_name: <job name>}` in its own thread `cron-<digest>` (`post_scheduled_message`). A failed run posts with `cron-notice:` instead. A post wakes only the members it @mentions (a failure notice nobody). The room is looked up from the job's profile: `room:<id>` alone failed on a room Crew created (`delivery_failed`, "no live Group Chat with that id on this machine", probed), because Crew's rooms live on the default profile's gateway, so Crew sends `room:<id>@default` (Hermes Desktop's target is `room:<id>@<the profile it talks to>`).

## Threads

Hermes 0.23.0 threads are only the `thread_id` on each `message.user`; routing acts only on the message that opens one. Crew follows Hermes Desktop's hosted room (`canonical-group-workspace.tsx`): every send opens its own thread (`thread_id` = the `event_id` Crew sends; the gateway logs the message under its own `user:<hash>` id), the room is one chronological stream of every thread, and there is no thread menu or New Thread (Desktop's New Thread belongs to its older client-driven rooms).

- **What a member sees.** A member's turn prompt holds only its thread's messages since that member's last turn there (`hosted_room_discussion._thread_messages`, watermark per thread and member). Its own earlier turns stay with it, since each member has one hidden session per room whatever the thread (`hosted_member_session`, title `Group: <room_id>`). So with a thread per message a member no longer sees peers' replies in earlier threads after its own turn, nor messages routed to someone else; Desktop has the same limit.
- **Sending while the room works.** A second message no longer supersedes the first, unless it is a Reply into that thread (`docs/flows/room-reply.md`: the answer in flight is dropped and shows "Stopped for your newer message"). Otherwise it opens its own discussion, which Hermes starts after the first settles (oldest pending thread first).
- **Reply** (like Desktop's hover Reply) continues a message's thread and prefixes the author's @handle: `docs/flows/room-reply.md`.

## Flow

### Room inspector (iPhone pushed page, Mac inspector column)

The settings sit between the header and Members, as standard grouped `Form` sections, all editable in place like the room's name (no Edit mode, no sheet; nothing pushes from the inspector).

- **Purpose** section: a one-line `TextField` (prompt "What this room is for"), like Desktop's (its placeholder says "in one line"; a vertical field would turn Return into a newline the server collapses). Saved when the field loses focus or on Return.
- **Shared Notes** section: a multi-line `TextField` (`axis: .vertical`, 3 to 12 lines, prompt "Facts every member should keep in mind"). Return inserts a new line; saved when the field loses focus, and flushed when the inspector goes away (iPhone Back, Mac close, another room selected), like the bot inspector. Footer: "Every member reads the purpose and notes before answering. Changes apply from the next message."
- **Who Answers** section: a menu `Picker` "Who Answers" with "Everyone", "Automatic" (only when `routing_modes` contains `auto` or the room already uses it) and "Lead: <name>" for each member (roster title, like the member rows). Saved on change. Footer by choice:
  - Everyone: "Every member answers a message that names nobody."
  - Automatic: "Hermes picks who a new message is for."
  - Lead: "<Name> decides who takes a new message that names nobody."
  - then always: "@mentions always reach the members you name."
  - and for Automatic and Lead: "A reply that names nobody reaches every member."
  - Why: Hermes routes only a message that opens a thread. Every Crew send opens one except a Reply (`docs/flows/room-reply.md`), which continues a thread, is never routed and reaches the members it names, or every member.
- **Lead in Members:** the lead's member row says "Lead" on its secondary line (before the role: "Lead · Engineer"), like Calendar's "Organizer" under an invitee.
- **Saving.** Each save is a room event every member and app sees, so there is no autosave while typing, and a save that changes nothing is skipped. Before each save Crew re-reads `groups.state` and sends the server's current value for every field the user did not edit; a purpose or notes save omits `routing` and `lead_member_id`, so it can never undo a routing change made elsewhere. A fresh `event_id` per save. Saves are serialized: a picker change right after typing a purpose waits for the purpose save and re-reads after it. While saving, the header's status line reads "Saving…" (as for a rename); on success the fields show what the server stored (purpose with collapsed spaces, notes trimmed).
- **Too long.** Purpose over 500 characters or notes over 4096 bytes: the section footer turns into a red line ("Purpose is limited to 500 characters." / "Shared notes are too long to save. Shorten them a little.", since bytes mean nothing to users and the limit falls earlier for non-Latin text) and nothing is sent until it fits; the typed text stays.
- **Failure.** A refused or failed save puts the server's message ("Hermes refused these settings." for a bare `invalid_params`, else the transport error) under the header in the same red status line as a failed rename, keeps the typed text and offers "Try Again" under it (the bot inspector's pattern), which resends that edit; the picker snaps back to the server's value.
- **Another app changes them.** The inspector reloads `groups.state` when it opens and on reconnect, and replaces only the fields that are not being edited (same rule as the bot inspector's profile draft).
- **Older gateway** (no `context` in `groups.state`): the three sections are hidden; the inspector is as before.
- **Offline:** the fields and picker are disabled, like the name.
- **Loading:** on iPhone the inspector is seeded from the open room's last `groups.state`, so the sections are there at once; on the Mac (inspector owned by the split view) they appear when its own read lands (no placeholder rows).
- **Long content:** the purpose scrolls inside its one line; notes grow to 12 lines then scroll inside.
- **Lead leaves the room:** rooms have fixed members, so a lead is always seated.

### Room transcript (iPhone and Mac)

Centred caption notices, the same view as "Renamed to …" and "Paused after …":

- `room.context_set` (no thread, like a rename): one line per thing that changed against the previous `room.context_set` in the log (an empty context before the first):
  - purpose set or changed: "Purpose: <purpose>" (cut at 80 characters with "…", since a notice is one short line); cleared: "Purpose removed"
  - notes changed: "Shared notes updated"; cleared: "Shared notes removed"
  - routing changed: "Everyone answers" / "Hermes picks who answers" / "<Name> decides who answers"
  - a save that changed nothing shows no notice.
- `room.assignment` (after its message): "<Lead> gave this to <names>" or, on `fallback`, "<Lead> is taking this" (Desktop's wording). Names are the room roster's display names (the bot's title when the room was made), joined as a list ("Ada, Linus and Grace"), wrapping when long.
- `room.routed` (after its message): "Assigned to <names>", "Assigned to everyone", or on `fallback` "Couldn't choose who answers, so everyone will". Names that left the roster are skipped; with none left the notice is dropped.
- The lead's routing turn: nothing beyond the assignment notice (it logs no message). A lead that picks itself reads "<Lead> is taking this". While it runs, the working row's footnote names the lead (it is working). A failed routing turn logs a fallback assignment and its `turn.failed`, which shows as today's error row under the lead; a deferred one gets today's Retry row; a cancelled one today's Stopped row.
- After a send, the room keeps its 2 s poll while the newest event is the user's own message, so the router's pause before `working` doesn't leave the working row 10 s late. (Only while the room is open; a room that never answers keeps that poll until it is closed, which costs one small request every 2 s.)
- **Empty room:** settings saved before the first message don't replace the members' empty state; the empty state's subtitle shows the purpose instead of "Say hello to start the conversation." when one is set. This is the one place the purpose shows in the chat: the pill already names the room, and a standing banner would sit over a transcript that is mostly about something else.

### Routine posts in a room

- A `message.user` with a `cron:` actor is a centred notice "Routine: <title>" (the job name without the `[bot:<profile>] ` prefix, as in Routines and the Bot Chat) followed by the output as a reply under the owning bot's avatar and name (`[bot:<profile>]` of the job name), never a user bubble: the owner's agent wrote that output, and the notice above says it came from a routine (Desktop's "Scheduled" badge). A tag naming a bot that is not a member still shows that bot; a deleted bot shows its profile name without an avatar; without a bot tag the output shows with no speaker line. Hermes' "[Output truncated to fit the room.]" tail shows as written.
- A `cron-notice:` post (a failed run): the notice and the text as an error row.
- Every run opens its own thread and shows in the room's one stream where it was posted. Members it @mentions answer under it as usual.

### New Routine: left out

A "Post Results In" room picker in New Routine is left out of this change (scope; #271 is reworking the routines code). The probe confirmed the target Crew would send, `deliver: room:<room_id>@default` (`room:<room_id>` alone fails with "no live Group Chat with that id on this machine"), and the transcript above already renders such posts, which Hermes Desktop can create today.

### Surfaces not touched

- Bot list: rooms keep their row (no preview or unread for rooms). A routine post moves the room's `updated_at`, so the room moves up as for any room event.
- Push: rooms have none; crew-push unchanged. With the routine banner on (`prefs.routines`, off by default) a room-delivered run still sends the cron banner, which opens the bot's chat, not the room (known limitation).
- Known limitation: rooms have no unread or status in the list, so a routine post, an assignment or a settings change is seen only when the room is opened, like every room event.
- Bot Chats: unchanged.
- Light and dark: system styles only.

## Evidence and tests

- `Tests/chat_probe/run.sh room-context` on `crew-test` plus a throwaway `crew-test-*` bot in a throwaway room: saves purpose and notes, a lead, a purpose-only save (stays `lead`), each refusal, an unaddressed message on a new thread (lead routing) and a second one in the same thread, Automatic on a new thread, and a routine on the throwaway that posts into the room; records `Tests/fixtures/rooms/context.*`; removes the routine, disbands the room and deletes the bot.
- `GroupSessionTests` replay the recorded log: context, assignment and routed notices, the routine post as notice + reply with the owner as speaker, every thread in one stream, and each send's params (`thread_id` = its own `event_id`). `Tests/chat_probe/run.sh room-routing` (throwaway bot and room, lead routing) sends two unaddressed messages through `GroupSession.send` and passes when the lead logged a `room.assignment` for each. `RoomContextTests`: save params (omitted routing on purpose/notes saves, the server's value for untouched fields), limits, the picker footer.
- Renders: `group-inspector`, `group-chat-context` (settings, assignment), `group-chat-routine` and `group-welcome` (purpose in the empty state), iPhone and Mac, light and dark.
