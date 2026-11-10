# Stop a running routine (#271)

Hermes 0.23.0 stops a live cron run: `POST /api/cron/jobs/{id}/cancel?profile=` answers `{cancelled: true, execution_id, detail}` when a run was in flight and `{cancelled: false, detail}` when nothing was, and leaves the schedule alone (`hermes_cli/web_routers/cron.py` `_cancel_cron_job_sync`, `cron/cancellation.py` `cancel_run`; a repeat cancel of the same run is idempotent). The run stops at its next cancel check (2.4 s on the real server) and books a `cancelled` ledger attempt with the reason `cancelled on request (Stop)`; the job's `last_status` becomes `cancelled` with `last_error: null` (an operator stop is not a failure). The scheduler also books skipped slots as one `missed` attempt (`missed ×N (<detail>)`, `scheduled_instant` = the first skipped slot, `cron/missed_runs.py`, `cron/executions.py` `record_missed_occurrences`) that never touches `last_status` or `last_run_at`. Recorded on the real server: `Tests/fixtures/scenarios/routine-stop/` (a `crew-test` routine run with Run Now, stopped, then removed).

## Where the state comes from

- `cron.manage list` (today's socket list) formats jobs with `_format_job`, which drops the execution ledger. Only REST `GET /api/cron/jobs?profile=<name>` carries each job's `latest_execution` (newest attempt: `id`, `status`, `error`, `claimed_at`, `finished_at`, `scheduled_instant`) and `live_execution` (the newest `claimed`/`running` attempt under a live owner; present as `null` when idle). So the Routines list moves to that REST call, which reads the profile's own store, so the `[bot:<name>]` filter and `scoped` check go (the REST list has taken `?profile=` since multi-profile cron, which Run Now already relies on). Mutations (add, pause, resume, remove) stay on `cron.manage`. The REST row names the id `id`, has the full `prompt`, `schedule_display` beside a `schedule` object, and `last_fire_error` as `{at, detail}`.
- Running: `live_execution` is present. While Crew's own Run Now request is open, the row also counts as running until the list shows an attempt claimed since the tap (2 s slack) that has finished, as Hermes Desktop does (`run-control.ts` `jobRunLive`), so a dropped request cannot hold Running.
- A server without the `live_execution` key (before 0.23) never shows Running or Stop; Run Now works as today, without the busy spinner.
- Last result: the newest attempt when it is `missed` and finished after `last_run_at` (a miss booked during a long run must not hide that run's result), otherwise `last_status` at `last_run_at` as today.

## Run Now blocks for the whole run

`POST …/trigger` returns only when the run ends (recorded: returned 2.4 s after the Stop, 11.4 s after the tap). Today the trigger holds the row's busy spinner for that time, so nothing else on the row is reachable, and `Connection.urlSession`'s 10 s idle timeout fails any run longer than 10 s with "Couldn't reach the server" while the run goes on. So:

- Run Now no longer takes the row's busy state; the row shows Running at once and offers Stop.
- The trigger request gets its own 2 h timeout (Hermes' own floor for reclaiming a stuck claim is 7 200 s).
- A trigger that fails while the server lists the job as live, or with a newer last run than before the tap, raised no real failure (the connection dropped, the app was suspended): no alert. Any other failure shows the alert as today.
- Run Now on a paused routine: Hermes force-fires it and resumes the job. The Paused badge clears on the next refresh (at the latest when the trigger returns).
- Switching bots while a Run Now or Stop is open: its reload and alert are dropped when it returns for a profile that is no longer shown.

## Routines tab (inspector on iPhone and Mac, same `RoutineList`)

- Running row: a caption line "Running" with a small system progress indicator, in place of the "Next run" line, secondary colour. The last-result line below stays (it describes the previous run).
- Stop: while the row is running, a borderless `stop.circle` button labelled Stop sits in the trailing slot before the ellipsis (the place Files and the App Store put the stop on a progress ring; HIG Progress Indicators: offer cancel next to the progress), and both the ellipsis menu and the context menu show Stop (`stop.circle`) in Run Now's place, as Shortcuts swaps play for stop while a shortcut runs. Leading swipe stays Pause/Resume. No confirmation: stopping is safe and the schedule is unchanged.
- After Stop: the row's busy spinner replaces the trailing buttons (as for every row action) and the caption reads "Stopping…" without its own indicator, until the list no longer lists that execution (`live_execution.id` differs from the reply's `execution_id`, so a run that starts right after does not keep it). Crew reloads every second for that, at most 30 s; after the cap the spinner clears, the row stays Running and Stop is offered again.
- Nothing was running (`cancelled: false`, the run ended between the last refresh and the tap, for example a scheduler run): an alert "Nothing Was Running", message "<title> had already finished.", OK; the list reloads to show the real result. Not framed as a failure.
- Stopped (`last_status` `cancelled`): last-result line "Stopped <relative time>", `stop.circle`, secondary colour, matching a stopped chat turn (`ChatView` "Stopped"). No reason line: every real reason is Hermes' raw `cancelled on request (…)`, which repeats the label.
- Missed: last-result line "Missed N runs <relative time>" (N from `×N`, time from `scheduled_instant`, else `finished_at`), `calendar.badge.exclamationmark`, orange (attention, like Delivery failed). The parenthesised detail is dropped: the next run is already on the Next run line.
- Other results, the `issue` line (red) and paused styling are unchanged.
- Pause while running: pauses future runs only; the live run goes on and Stop stays, so Paused and Running can show together. Delete while running: Hermes cancels the run with the job; the existing confirmation ("It stops running and is removed from the server.") already says so.
- VoiceOver: "Running", "Stopping…", the Stop button, "Stopped, 2 minutes ago" and "Missed 3 runs" read as text; the progress indicator is decorative.
- Dynamic Type and long names: caption lines wrap; the title stays one line, truncated, as today.
- Light and dark: system colours only.

## Refresh

- Run Now: the row shows Running at once; the trigger's return reloads the list.
- Stop: reloads every second until the stopped execution is gone (above).
- A run the scheduler or another device started: shown on the next `cron.changed` or the 20 s poll, as today (the job's `fire_claim` write changes `jobs.json`; `cron.changed` only watches the gateway's own home, so other bots wait for the poll). Its end shows the same way.

## Run history

Crew has no per-routine run list. The row's last-result line is the history surface the issue names ("where the row shows the last result"). The stopped run's own session still appears in inspector > Conversations (source cron) under its own title; Hermes adds "CANCELLED · …" titles only in the run-history endpoint, which Crew does not read. Out of scope.

## Other surfaces

- Bot Chat, bot list: none. A stopped run delivers nothing, so there is no Bot Chat hand-off or preview change. The run's own session is unchanged.
- Push: none by default (the routine banner is off). With `prefs.routines` on, a stopped agent run sends no banner: Stop interrupts the agent (`cron/scheduler.py`) and crew-push returns early on an interrupted run (`server/crew-push` `hooks.py`). Read from source, not probed (the probe cannot see pushes).
- Offline: the list keeps its last jobs; Stop fails with the connection alert.
- Error loading: the existing "Couldn't Load Routines" state.
- Empty: the existing "No Routines" state.

## Verification

- Unit: `RoutineStopScenarioTests` decodes the recorded REST rows (idle, running, stopped, a scheduler-started run, the two cancel replies) and a missed row built from the source contract, and asserts each row's running state, label, symbol and time; the store tests run Run Now and Stop through a stubbed `URLProtocol` (Stop reachable while the trigger is open, no alert when the trigger fails while live, "Nothing Was Running" on `cancelled: false`, a Stop that settles on its own execution).
- Real server: `Tests/routine_probe/run.sh` drives `RoutineStore` on `crew-test` with the app's 10 s session: Run Now, Running, Stop, Stopped, a second Stop answering `cancelled: false`; then an every-minute routine the scheduler starts on its own, Paused while running (still live), and Delete while running. It removes the routines and their run sessions and records the fixtures.
- Missed is not reproducible on the real server without stopping it, so its row is synthesized from the source contract.
- Renders: `inspector-routines` on iOS and Mac, light and dark, with a running, a stopped and a missed routine: `docs/flows/renders/routine-stop-*.png` (the iPhone frame ends at the running row; the Mac frame shows all rows).
