# Slash command suggestions (#110)

Typing `/` as the first character of an empty composer lists the bot's commands in a card above the field, like the @mention picker.

## Data

- `commands.catalog {profile}` on every attach of a bot chat (`ChatSession.slashCommands`), one request, kept when a later fetch fails. Rows are the catalog's `pairs` (name, description) in Hermes' order (Session, Configuration, Info, Tools & Skills, then skills).
- Kept: skills, and built-ins whose `commands[name].desktop` is null. Dropped: `terminal` (TUI-only: /clear, /copy, /paste, /redraw, /quit), `hidden` (/model, Crew has its own model menu), `settings`, `advanced`, `composer-voice`, and the 3 TUI rows with no `commands` entry. Aliases (/compact) are not in `pairs`. 121 of 152 on `crew-test` (Hermes 0.22.5, `Tests/fixtures/commands.catalog.v0.22.5.json`).
- `complete.slash` is not used: it returns terminal commands and aliases and caps skills at 4.

## Surfaces

- **Composer, bot chat, iPhone and Mac:** the whole draft is `/` plus non-space characters. The card shows rows whose name starts with the typed text (case-insensitive): the `/command` in monospace accent colour, its description in secondary subheadline, clamped to 2 lines. Same glass card, 240 pt max height, scroll and fade as the mention picker. Light and dark checked in renders (`chat-slash`).
- **Pick:** tap or click a row: the draft becomes `/command ` and focus stays in the field. The space ends the match, so the card closes. Return keeps sending, matching the mention picker (PLAN.md: Return does not pick a suggestion); no arrow-key selection, the same as mentions.
- **Group rooms, inspector viewer:** no card (rooms send through `groups.send`, no catalog).
- **Bot list, push, inspector:** unchanged; see Running a command.

## States

- **Empty filter:** no match hides the card, like mentions.
- **Loading / failed fetch / not yet attached:** empty catalog, no card; typing works as before.
- **Offline:** the catalog fetched on the last attach stays and the card still shows; picking only edits the draft.
- **Long content:** descriptions clamp to 2 lines (iPhone truncates the usage hint, Mac fits one line); the list scrolls past 240 pt; long names stay on one line.
- **Coexistence:** the @mention picker needs `@` at the start or after whitespace, so the two never show together; `@file:` path completion is unchanged.

## Running a command (#187)

Sending a draft whose first word is exactly a catalog name runs it the Hermes way; anything else (`/foo`, `/statusx`, `what does /status do`) is an ordinary prompt. Exact match matters: `slash.exec` prefix-matches, so `/foo` ran `/footer` on `crew-test`.

- **Built-ins:** `slash.exec {session_id, command}`, then the transcript reloads from `session.resume` (so /undo and /retry show the server's rows), then the directive is applied:
  - plain `output` (or `type: exec|plugin`): a centered caption with the typed command, then the output in the reply code-block card (monospace, horizontal scroll, copy menu). `/status`, `/help`, `/usage`, `/config`.
  - `prefill` (/undo): the notice goes under the caption and the undone message returns to the composer as typed (a skill turn returns as `/skill arg`, not its scaffold).
  - `send` (/retry): the notice, if any, under the caption; the message is submitted as a normal prompt bubble.
  - `alias`: the target runs through `slash.exec`.
  - RPC error (`usage: /steer <prompt>`): the caption plus the red error line, like a failed turn.
- **/compress and /new:** the Chat Options actions from #115 (`docs/flows/bot-chat-new-compact.md`), without their confirmation since typing the command is the intent. /compress runs `session.compress` (now with a 5 minute timeout: 73 s on `crew-test`, `slash.exec` times out) and puts the summary headline under the caption; /new retires the Bot Chat and opens a fresh one.
- **Skills:** `command.dispatch {session_id, name, arg}` returns `{display, message}`; `message` is submitted, the bubble shows `display`. History has no display text for that row (recorded in `Tests/fixtures/skill-invocation.history.json`), so `Prompt(raw:)` maps the `[IMPORTANT: The user has invoked the "x" skill` scaffold back to `/x arg`, live and after reload.
- **Not offered:** `/branch`, `/resume`: a Bot Chat is one session per bot. Typed anyway, they go as prompts.
- **While a turn runs:** a command is queued (Queued bubble, never a steer) and runs when the turn ends; commands after it in the queue follow.
- **In flight:** the caption shows with a small spinner until the reply arrives.
- **Persistence:** command cards are local. They stay through reloads and syncs in this app session, placed by when they finished, and are gone after relaunch or on other devices (Hermes stores nothing for them). They never become the bot-list preview, time or unread, and send no push.
- **Offline / no runtime:** nothing is sent, as with prompts. A failed call shows the error line.
- **Long content:** output keeps its line breaks; wide lines scroll horizontally in the card; `/help` is long and scrolls with the transcript.
- **Group rooms:** no catalog, unchanged.
- Recorded replies: `Tests/fixtures/slash.exec.v0.22.5.json` (`Tests/chat_probe/run.sh slash-raw` with `SLASH=... RECORD=1`); end-to-end on `crew-test` with `SLASH_LINES='/status;;/undo;;...' Tests/chat_probe/run.sh slash-run`. Renders: `chat-slash-output`.
