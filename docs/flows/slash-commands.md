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
- **Bot list, push, inspector:** unchanged; a sent `/command` is an ordinary prompt.

## States

- **Empty filter:** no match hides the card, like mentions.
- **Loading / failed fetch / not yet attached:** empty catalog, no card; typing works as before.
- **Offline:** the catalog fetched on the last attach stays and the card still shows; picking only edits the draft.
- **Long content:** descriptions clamp to 2 lines (iPhone truncates the usage hint, Mac fits one line); the list scrolls past 240 pt; long names stay on one line.
- **Coexistence:** the @mention picker needs `@` at the start or after whitespace, so the two never show together; `@file:` path completion is unchanged.

## Not in this change

- Sending runs nothing special: `prompt.submit` passes `/status` to the model as text (verified on `crew-test`). Running needs `slash.exec {session_id, command}` (built-ins, returns `{output}` with no transcript row) and `command.dispatch {session_id, name, arg}` (skills, returns `{display, message}` to submit), plus a transcript surface for the output. Follow-up issue.
