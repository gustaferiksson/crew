# Send Later

Messages on iOS 18 and later: + menu > Send Later, pick a time, and the message waits at the end of the chat as an outlined bubble with its send time. Touch and hold it to send now, edit the time or delete it. Apple's servers send it at that time even when the phone is off.

Crew's version must fire on the Hermes server for the same reason, and once it fires the message must be an ordinary user prompt in the bot's Bot Chat that the bot answers. **Status: blocked on Hermes 0.22.5. Nothing is built.** Crew does not fake it with a device-side timer (it would not fire while the device is off or Crew is suspended, which is the point of the feature). The flow below is what Crew ships once Hermes offers the missing piece; "Blocked on Hermes" says exactly what is missing.

## Blocked on Hermes

Probed on `crew-test` (server 0.22.5, `GET /api/status`) and read in a local Hermes checkout (`ae3f9f9cb1`, 2026-10-13; not identical to 0.22.5):

1. **One-shot schedules work.** `POST /api/cron/jobs?profile=crew-test {schedule: "2026-11-08T09:00:00", repeat: "once", deliver: "bot-chat", paused: true}` returned `schedule {kind: "once", run_at: "2026-11-08T09:00:00+00:00"}`, `repeat {times: 1}`, `state: paused` (job deleted right after). `parse_schedule` (`cron/jobs.py`) takes any ISO timestamp, with an offset or naive in the Hermes timezone, and `in 30m`. `GET /api/cron/delivery-targets` lists `local` and `bot-chat:<profile>` for every profile. So scheduling, Edit Time (`PUT /api/cron/jobs/{id} {updates: {schedule}}`), Send Now (`POST …/trigger`) and Delete are all there.
2. **Missing: delivering the job's prompt as the user's message.** A cron job never puts its prompt into the Bot Chat. It runs a separate model turn on the prompt in its own `cron_<job>_<time>` session (no Bot Chat context), and `deliver: "bot-chat"` then hands that turn's *output* to the Bot Chat wrapped as `[Cronjob "<name>" output — scheduled job, not the user. Review it, act on anything that needs action, and summarize for the chat.]` (`cron/scheduler_delivery.py` `_deliver_to_bot_chat`, hard-coded). The row lands as `role: user, display_kind: internal_notification` (recorded: `Tests/fixtures/scenarios/routine-delivery/crew-test-peer.history.json`), which Crew rightly shows as a "Routine:" notice. The bot is told the text is *not* from the user and summarizes it instead of answering it. No `CronJobCreate` field (`hermes_cli/web_models.py`) and no gateway method (`tui_gateway/`) schedules a verbatim user prompt.
3. **On 0.22.5 only: delivery into a Bot Chat Crew has opened is refused** with `not_found` (`routine-delivery.md` > Delivery refused). The newer checkout replaces that with a live-owner mailbox, so a Hermes upgrade may remove this gap by itself.

What Hermes would need: the consumer half already exists in the newer checkout. Its live-owner mailbox (`tools/bot_live_delivery.deliver_to_live_owner`, consumed by `tui_gateway/session_notifications.py` `_poll_bot_live_delivery_once`) submits whatever text it holds as an ordinary user prompt (`_run_prompt_submit`, no `display_kind`) once the Bot Chat is idle, and the CLI lane (`hermes chat -c "Bot Chat" --create-if-missing`) covers a chat nobody holds. Missing is only a cron delivery mode that, at `run_at`, writes the job's `prompt` into that lane verbatim, with no cron model turn, no `[Cronjob …]` wrapper and no bot author, and records the outcome on the job.

Considered and rejected:

- `no_agent` + `script` job printing the message: the stdout still arrives inside the Cronjob wrapper as `internal_notification`, so the bot still reviews instead of answering. A script that runs `hermes chat -c "Bot Chat" -Q` itself would be a second writer to a chat the live owner holds, and needs a script file on the server (a server change).
- A cron prompt like "say exactly: …": the user's words become cron output, then a routine notice, then a summary.
- `/loop` and `/heartbeat` (`hermes_cli/loops.py`): they wrap the text in a "automatic wakeup from the /loop the user set" template and run on an interval (30 s floor), not at a timestamp.
- A device timer, a background task or a local notification that sends from the device: does not fire while the device is off; ruled out by the feature.

No job was fired on the real server: a delivered run makes the bot reply in its Bot Chat, which pushes to the user's devices. The recorded fixture already shows the landed row.

## Model (when unblocked)

- A Send Later message is one one-shot cron job on the bot's profile: `schedule` = the chosen instant as ISO 8601 with the device time zone's UTC offset *at that instant* (never naive, so the Hermes timezone cannot shift it, and a daylight-saving change inside the 14 days is honoured), `repeat: "once"`, the scheduled-prompt delivery, `prompt` = exactly what a normal send would submit: the text, attachments as uploaded `@file:`/`@image:` lines, and the identification note `prompt.submit` appends, so mentions behave the same after it fires. Name `[send-later:<profile>] <first line, 40 characters>`.
- `ChatSession` owns the bot's pending Send Later jobs for an open Bot Chat (main window and Mac chat window alike): `cron.manage list` filtered to `[send-later:` names, loaded on attach, on `gateway.ready`, after each mutation, and once at each job's `run_at`. `cron.changed` is not relied on (it watches only the gateway's own HERMES_HOME). The same pending messages show on iPhone, iPad and Mac.
- Hermes Desktop and the CLI list these jobs as ordinary routines named after the message; that is accepted.

## Composer (iPhone, iPad, Mac main window, Mac chat window)

- The + menu gains **Send Later** (`clock`) as its last item (on the Mac, after Paste). The + button's accessibility label becomes "More" since it no longer only attaches. Bot Chat only (see Rooms).
- Choosing it adds a **Send Later strip** above the text field, like Messages: a clock symbol, a `DatePicker` (`.date` + `.hourAndMinute`, `.compact` on both platforms; the value shows in the tint colour as relative day and time in the locale's 12- or 24-hour format), and an xmark to cancel. Default: the next full hour at least 15 minutes out; 5-minute steps (the HIG's coarser-interval advice); range now + 1 minute to 14 days. Tapping the value opens the system calendar and time editor.
- While the strip shows, Return/Send always schedules, even while the bot is working (no Steer/Queue menu), and the placeholder reads "Send Later". The text and tray clear like a normal send; the strip goes away. Offline, the send button is disabled as it is for a normal send. A draft that is a slash command cannot be scheduled (the send button is disabled with the strip up).
- Attachments are uploaded at schedule time, as a normal send uploads them.
- VoiceOver: the strip reads "Send later, <date and time>, adjustable"; the xmark is "Cancel Send Later".

## Pending bubble (Bot Chat)

- Order at the end of the transcript: the live turn, then Waiting/Queued bubbles (`Transcript.waiting`), then Send Later bubbles, earliest send time first.
- Look: the user bubble shape with a clear fill and a 1 pt dashed stroke in the user-bubble colour, text in that colour (as the existing pending bubble does, `UserBubble.swift`), and under it a trailing caption "Send Later · <relative day and time>" (secondary). Same width rules, markdown and attachment thumbnails as a sent bubble.
- Touch and hold (iPhone, iPad), secondary click (Mac): context menu **Send Now** (`paperplane`), **Edit Time** (`clock`), then **Delete** (`trash`, destructive, last). Edit Time opens the same compact picker in a popover on the bubble (on iPhone it adapts to a sheet with a medium detent) with Done.
- Send Now = `POST /api/cron/jobs/{id}/trigger`; the caption becomes "Sending…". Edit Time = `PUT …/jobs/{id} {updates: {schedule}}`. Delete = `DELETE …/jobs/{id}` and the text and attachments go back into the draft, like Remove from Queue, with no dialog.
- An action on a job the server already fired or removed fails quietly: no alert, the bubble resolves through the next refresh.
- Editing the text itself is not offered (Messages only edits the time); Delete returns it to the draft for editing.
- VoiceOver: "Scheduled for <date and time>, <text>", with accessibility actions Send Now, Edit Time and Delete.
- Jump-to-bottom and the bottom anchor treat pending bubbles as content, so a new pending bubble is visible after it is created.

## When it fires

- The user row arrives through the read-position refetch (it runs on Hermes' Bot Chat owner, like routine delivery) or live when Crew's runtime is the owner. The pending bubble goes away only when the real row is in the transcript, never on the cron list alone, so there is no gap: past its time it shows "Sending…" until then. The real row is an ordinary blue bubble with its normal time; the bot's work log and reply follow.
- Bot busy at fire time: Hermes holds it until the running turn ends; the bubble keeps "Sending…".

## Bot list (iPhone and Mac sidebars)

- Pending: preview stays the last real message (Messages shows the scheduled text only inside the chat). No badge.
- After firing: preview is the user's message, then the reply, at their own times. The read position moves past the user's own fired row, as for any message the user sends, so only the bot's reply marks the row unread.
- Working from `session.active_list`, as today.

## Push

- Firing sends nothing of its own: the user's text is not pushed back to the user. The bot's reply in the Bot Chat sends the normal reply push (crew-push's Bot Chat scope). With `prefs.routines` on, crew-push must skip the cron banner for `[send-later:` jobs; Crew ships Send Later together with the crew-push release that adds that filter, so one fire never gives two banners.

## Inspector

- The Routines tab hides `[send-later:` jobs (a name filter next to today's scoped/owner filter in `Routines.swift`). The Info tab adds nothing; the pending bubbles are the only surface (Messages has no list of scheduled messages either).

## Rooms

- Excluded. A room prompt fans out to several bots through Crew's own room relay, which runs on the device; cron can only target one profile's Bot Chat. Send Later is absent from a room's + menu.

## Other conversations sheet

- Excluded: cron targets only the canonical Bot Chat. Send Later is absent from that composer's + menu.

## States

- Fresh bot with no messages: the pending bubble shows below the usual empty-chat state; the preview stays empty until it fires.
- Server error while scheduling (online): the draft stays with the strip, and Crew shows the usual send-failure alert "Couldn't schedule the message." with the server's error. Nothing is queued on the device.
- Offline: scheduling is disabled like Send; pending bubbles render from the last list; Send Now, Edit Time and Delete are disabled until reconnected. The message still fires on the server.
- Time passed while offline: the bubble shows "Sending…" until the refetch shows the real row.
- Delivery failed (job `last_delivery_error`, provider error, refused): the dashed bubble's caption becomes a red "Not Sent" with the warning symbol, and the menu becomes **Try Again** (trigger), **Edit Time**, **Delete**. The error's sentence shows on tap, like `delivery-failure.md`. VoiceOver: "Not sent, <text>".
- Missed (the server was down past `run_at` plus Hermes' 120 s one-shot grace, `cron/jobs.py`): Hermes retires the job without running it; the bubble is "Not Sent" with Try Again, never stuck on "Sending…".
- Job paused by Hermes (`state: paused`, e.g. scheduler preflight): "Not Sent: Hermes paused it."
- Bot deleted: its jobs go with the profile.
- Long content: the bubble wraps like a sent bubble; the job name truncates at 40 characters, the prompt is unbounded.
- Several pending messages: each its own bubble, ordered by send time.
- Clock skew: the server's `run_at` is shown, in local time.
- Light and dark: the dashed stroke and text use the user-bubble colour (system blue, #0040DD under Increase Contrast); the caption is secondary.
- Dynamic Type: the caption wraps under the bubble; the strip puts the picker under the label at accessibility sizes.

## Verification (when unblocked)

- Record a scenario on a throwaway `crew-test-*` bot (one Send Later fired, the reply, rosters before and after) into `Tests/fixtures/scenarios/send-later/`; scenario tests assert the pending bubble from the recorded cron row, the real bubble after firing, the bot list preview, time and unread, and the Routines tab filter.
- Renders: `chat-send-later` (pending and failed bubbles) and the composer strip, iOS and Mac, light and dark.
- Open: check against real Messages whether its "Send Later" time label sits under the dashed bubble, as specced, or above it.
