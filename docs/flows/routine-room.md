# Routines: post into a room (#349)

Hermes v0.23.1 delivers a cron run into a hosted room when the job's `deliver` is `room:<room_id>[@<profile>]` (`cron/scheduler_delivery_room.py`): the run's output becomes one `message.user` in the room's log with actor `cron:<job id>` and the job name, in its own thread. It starts a round only for the members it @mentions (`@all` for everyone); otherwise it is just a message. `@<profile>` names the profile whose gateway hosts the room, not the routine's bot: Crew's rooms live on the dashboard gateway Crew talks to, so the target is `room:<room_id>@default`, as probed in #270. The server checks no membership; offering only the bot's own rooms is Crew's choice, so the post sits next to the bot's own messages. A room that no longer exists fails the delivery with `room:<id>@default: no live Group Chat with that id on this machine` (`last_status` `delivery_failed`, `last_delivery_error`).

Desktop's Routines pane (`hermes-bots/cron.tsx`) offers "Send results to": "Run history only" (no `deliver`, the server's `local`) or "<bot>'s chat" (`bot-chat`); rooms appear only as a copyable `deliver:` target in Desktop's Room settings. Crew keeps its default (no `deliver`, run history only, see PLAN.md "New routines") and adds the bot's rooms. `bot-chat` stays out (Bot Chat admission is still refused for most bots, `routine-delivery.md`).

Crew had no Edit Routine; this adds the smallest one, so a destination can be changed: the same sheet, prefilled. Saves go through REST `PUT /api/cron/jobs/{id}?profile=` with `{"updates": {…}}` holding only the fields the user changed (`cron.manage` has no update action). `schedule` is sent as a string, which `update_job` parses like `add`.

## New Routine and Edit Routine (iPhone sheet, Mac sheet, same `RoutineEditor`)

- A section after the schedule: a menu `Picker` "Post To" with "Don't Post" first, a divider, then each room the bot is a member of (`GroupStore.rooms(with:)`, list order), by room name. New Routine starts on Don't Post and sends no `deliver` for it.
- Footer: Don't Post says "Each run's result stays in its own conversation under Conversations." A room says "Each run posts its result in <room>. Members answer only when the result @mentions them or @all."
- No rooms (the bot is in none): the picker shows Don't Post alone and the footer adds "Create a room with <bot> to post results there." Server without rooms (`groups.isSupported` false): no section.
- Edit Routine: title "Edit Routine", Save instead of Create; reached from Edit… (`pencil`) in the row's ellipsis menu and context menu, presented from the inspector like New Routine. Name, prompt, schedule and destination are prefilled: the name without its `[bot:<profile>] ` prefix (kept on save), the schedule as its preset when it is one Crew writes (hourly, daily, weekdays, weekly), else Custom with the server's expression.
- Read back: a saved `room:<id>@…` selects that room. A room missing from a successful `groups.list` (disbanded) shows as an extra option "Removed Room", selected (just "Room" while the list has not loaded, offline or after a failed list, so a live room is never called removed), so the picker never renders blank and the user can move the routine elsewhere. Any other target (`bot-chat`, `origin`, a platform, a list) shows as one extra option with its raw value ("Bot Chat" for `bot-chat`), selected, and is left untouched unless the user picks another destination.
- Save sends only changed fields, compared with the stored values (an hourly routine reads back as Custom `every 60m`, so an untouched schedule is never resent, which would recompute `next_run_at`); no change at all just closes the sheet. Don't Post on an edit sends `deliver: "local"` (the server's value for it). A routine with no prompt (script or skill jobs) can still be saved with an empty prompt.
- Edit lives in the ellipsis and context menus, next to Run Now, Pause and Delete; a row tap stays inert (the row already holds the ellipsis and Stop buttons; a tap-to-edit row is a follow-up).
- Error and offline: the server's message, or "Crew couldn't reach the server.", shows in the sheet's error section as Create does today; the sheet stays open with the edits.
- Light and dark, Dynamic Type: system Form controls only. Long room names truncate in the menu like any picker.

## Routine row (Routines tab, iPhone and Mac)

- A room routine gets a caption line under the schedule: `bubble.left.and.bubble.right` "Posts to <room>", secondary colour. A room missing from a successful list reads "Posts to a removed room"; before the list loads, offline or on a server without rooms, "Posts to a room". Run-history routines and other targets show no line (unchanged).
- Disbanded room: the next run fails delivery; the row's existing last-result line says "Delivery failed" (orange) and the red issue line shows Hermes' message.
- VoiceOver reads the line as text; it wraps at large sizes.

## Room (iPhone and Mac)

- Unchanged: a routine post is a centred "Routine: <title>" notice plus the output under the owning bot, in its own thread, where it lands in the stream (PLAN.md "Room settings"). A member it @mentions answers in that thread.
- A failed run: with no `failure_deliver`, failures follow `deliver`, so the failure notice is posted into the room too (a `cron-notice:` post that never starts a round), shown like any routine post.
- Long output: Hermes cuts a post at 64 KiB and ends it with "[Output truncated to fit the room.]"; it renders as long text like any message.
- Arrival: the open room picks it up on its next poll (10 s idle). Rooms have no unread, preview or push (PLAN.md), so the bot list does not change.

## Other surfaces

- Bot Chat, bot list preview, push: none. A room routine delivers nothing to the Bot Chat. The run's own session is still listed in inspector > Conversations (source cron).
- Run Now, Stop, Pause, Delete: unchanged.

## Verification

- Unit (`RoutineRoomTests`): decode the recorded REST rows (a room routine, the same routine edited, after a run, after its room was disbanded with its delivery failure, a `local` routine, a routine-stop row without `deliver`) and assert the destination, name, schedule, result and issue; parse Hermes' target grammar; assert the PUT bodies through a stubbed `URLProtocol` (only the changed destination, a rename keeps the prefix, an untouched edit sends nothing, an untouched foreign target is not sent).
- Real server: `Tests/routine_probe/run.sh room` on a throwaway `crew-test-*` bot and room with `crew-test`: `RoutineStore.create` with a room destination (server stores `room:<id>@default`), read back; edits to Don't Post and back (next run unchanged); a rename, prompt and weekday-preset schedule edit (prefix kept, schedule read back as sent, an untouched edit leaves the next run alone); Run Now, the `cron:` post seen in `groups.log`; then disband the room, Run Now again and record the delivery failure. Deletes the routine, room and bot.
- Not covered by a test or probe: the editor's footers and extra picker options (removed room, foreign target, not-loaded "Room"), and a Don't Post create sending no `deliver` (unchanged code path). The removed-room row line is in the Mac render.
- Renders: Edit Routine with a room chosen and the Routines tab with a room routine, iOS (private simulator) and Mac: `docs/flows/renders/routine-room-*.png`.
