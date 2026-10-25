# Routine output in the Bot Chat

A routine with `deliver: "bot-chat"` (Hermes 0.22.5) hands its output to the bot's own Bot Chat as an inbound turn; the bot reviews it and replies there. Hermes stores the hand-off as a user row with `display_kind: internal_notification` whose content is `[Cronjob "<job name>" output — scheduled job, not the user. Review it, act on anything that needs action, and summarize for the chat.]`, a blank line and the run's output (`cron/scheduler_delivery.py` `bot_chat_message`). Recorded on the real server: `Tests/fixtures/scenarios/routine-delivery/` (a throwaway bot whose Bot Chat the delivery itself created; the bot used the `skill_view` tool, then replied).

Crew showed that row as the user's own bubble, because only `Message from …` internal notifications were recognised. The user did not write it, so like Messages' system lines it becomes a quiet centred notice, and the bot's reply under it is what the user reads.

Who makes such routines: Crew's Routines sheet sends no `deliver`, so today they come from the bot itself (the `cronjob` tool) or the CLI. Crew does not add a delivery picker here.

## Bot Chat (iPhone, Mac main window, Mac chat window)

- Matching: the row's text (`display_content ?? content`) starts with `[Cronjob "` and contains `" output — scheduled job`, with kind `internal_notification` or none (the live path may lack the kind). Any other `internal_notification` row keeps today's handling.
- The hand-off is a centred caption notice "Routine: <title>", the same view as "Switched to <model>" (`noticeText`). `<title>` is the job name without Crew's `[bot:<profile>] ` prefix (same rule as `RoutineJob.title`), so it matches the Routines list. Never a user bubble. VoiceOver reads it as static text; it scales with Dynamic Type and wraps.
- The bot's work log and reply follow under the notice in the same turn. The raw output is not shown and the notice does not expand (no notice does): the reply summarizes the output, and the full run stays in its own session (inspector > Conversations, source cron).
- Arrival: the turn runs on Hermes' own Bot Chat owner, not on Crew's runtime (see Delivery refused), so an open chat sees it through the read-position refetch, as finished rows, like a bot-to-bot exchange (`agent-messages.md`). A message the user sends meanwhile is an ordinary prompt.
- Long output: never rendered. A long job name wraps.
- Light and dark: secondary system colour only.

## Bot list (iPhone and Mac sidebars)

- Preview: a routine hand-off is a preview candidate like a bot-to-bot message. While its reply is still empty the row reads "Routine: <title>" at the hand-off's time; after the reply, the reply at the reply's time. Other notices (model switch etc.) never become the preview.
- Server fallback: when the 20-row window has no user row (a long tool run), the row shows the server's preview; a raw brief there is shown as "Routine: <title>" too (recorded `profiles.during.json`: Hermes' preview is the truncated brief).
- Time: the preview's own time, as above. Unread: `message_count` past the read position, so the hand-off alone marks the bot unread, and the reply keeps it so.
- Working: from `session.active_list`, as today.

## Push

- The bot's reply in the Bot Chat sends the normal reply push (the hand-off is not a user turn, the reply is a Bot Chat reply).
- The cron run sends the routine banner only with `prefs.routines` on, with the job name as subtitle (crew-push 0.6.9 reads it from the 0.22.5 cron execution identity), and never for a run whose reply is `[SILENT]`. Known gap: with `prefs.routines` on, one bot-chat routine run gives two banners (routine, then reply).

## Search

- Server search can match words of the brief; the hit's snippet is the raw text. Known gap, not changed here.

## States

- Error: the bot's turn fails after the hand-off: the notice stays, the failure shows under it as for any turn.
- Offline: rendered from the loaded transcript.
- Fresh bot whose first row is a hand-off: the 20-row window starts at that user row, so the notice and reply are the transcript and the preview; no empty state.
- Delivery refused: on 0.22.5 a Bot Chat that Crew already opened refuses the hand-off with `not_found` (`gateway/platforms/api_server_bot_chat.py` `_refusal`), which today covers most bots. Nothing lands in the chat; the inspector's Routines row shows the run's delivery error. Fixing that is server-side and out of scope.
- Inspector: no change.
