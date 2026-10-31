# Hermes warnings in a turn (#129)

Hermes sends its warnings through `status.update`, the same slot as live progress. Crew shows that slot as the footnote under "Working for Xs", so a warning flashes there for a moment, is replaced by the next status or cleared by `message.complete`, and is gone. Two routes reach it:

- `kind: warn` (`_emit_warning`): degraded paths where the turn goes on but the user must know, for example "⚠️ This turn stopped making progress…", "⚠️ Turn aborted by the liveness watchdog…", "⚠ Context is over the compression threshold… compression is currently blocked… Run /new to start a fresh session or /compress to retry immediately.", "⚠ Compression summary failed…", "⚠️ Compression refused…", "⚠ Auxiliary <task> failed: …".
- ⚠ diagnostics on the lifecycle rail, which the gateway re-tags `kind: compacting` because they mention compression: "⚠️  Session compressed N times — accuracy may degrade. Consider /new to start fresh." (after 2 or more compressions) and the multi-line "⚠ Compression model … Auto-lowered this session's threshold … To make this permanent, edit config.yaml …". Hermes stores the latest one and replays it on a session's first turn.

Hermes Desktop drops both from its status text. Dropping them in Crew would hide the ones the user can act on here: Compact Chat and Start New Chat (Chat Options) are exactly what the compression warnings ask for, and a stopped turn can be sent again. So Crew keeps them, in a quiet, stable place.

## Treatment

- A `status.update` whose `kind` is `warn`, or whose text starts with ⚠ (U+26A0, with or without the emoji selector), is a warning; the rule covers every such line, not a list. Hermes puts its `log_prefix` before the ⚠ only for subagents, whose statuses never reach the parent chat, so the first character is the test (checked in the recording below).
- A warning never becomes the live footnote; the footnote keeps the last progress status (for example "🗜️ Compacting context…"), or nothing.
- Each `message.start` clears the footnote, so a status left from before the turn (the `ready` that ends Compact Chat, seen in the recording) is not shown as the new turn's Working text now that the warning no longer overwrites it.
- It is stored on the running turn. With no running turn (a late post-turn path such as title generation) it is dropped: nothing to attach it to, and those paths are not actionable.
- It shows inside that turn, under the work log header and above the reply, so it never moves while the reply streams below it: a footnote `Label`, `exclamationmark.triangle.fill` in orange (Apple's warning tint, readable in light and dark) and the text in secondary, Hermes' leading ⚠ and spaces removed. Like Messages' "Not Delivered": part of the message it belongs to, no banner, alert or haptic. An error turn also has its red error line below the reply; orange above, red below reads as two different things, like Mail's warning and error badges.
- Only the first line shows. The lines after it are `config.yaml` snippets and terminal commands Crew can't act on (the reason ℹ diagnostics are dropped, PLAN.md #102). The first line wraps and never truncates.
- The same text twice in one turn shows once (Hermes replays, and a mid-turn reattach replays the turn's events again); two different warnings show as two lines in arrival order.
- ℹ diagnostics are still dropped, unchanged.
- Live only: Hermes never writes warnings to history. The line survives the turn's end and the history sync that follows (the sync copies warnings for every turn it matches by id, completed or not), and is gone once the chat reloads (relaunch, Compact Chat, Start New Chat, a reconnect after the turn ended). Desktop's own warning-like system rows behave the same; persisting them needs a Hermes change.
- Cost: one character check per `status.update` (not per token), as today. Nothing new observes streamed text.

## Surfaces and states

- Bot chat on iPhone and Mac (main window and chat window share the session), light and dark.
- Other Conversations (inspector, Mac inspector column and iPhone page) uses the same `ChatView`, so a live turn there shows the line too, wrapping at the inspector's width.
- A plain reply turn (no work log) keeps the line after the header goes away.
- Stopped turns: the line above the reply, "Stopped" below it as today. Failed turns: the same, with the red error line below.
- A steer splits the turn: the warning stays on the turn that was running when it arrived.
- Turns from another bot ("Message from"): same line, same rule.
- Long content: the first line wraps over as many lines as it needs at every Dynamic Type size; the text is selectable.
- VoiceOver: "Warning, <text>".
- Offline: nothing new; the line stays until the chat reloads.
- Bot list (preview, time, status, unread), push and mention peek: unchanged. The peek's live status keeps showing progress only, since it reads the same footnote value.
- Group rooms: unchanged; rooms read `groups.log`, which has no `status.update`.

## Tests

- Fixture: `Tests/chat_probe/run.sh compressed` on `crew-test` sends two short prompts with Compact Chat after each, then "Reply with just: hi", recording every event (`Tests/fixtures/chat.compressed-turn.v0.22.5.jsonl`). Replayed: the footnote never shows a ⚠ line, the last turn keeps the warning after `message.complete`, the reply is unchanged.
- `kind: warn` with Hermes' verbatim watchdog text after a compacting status: the footnote keeps the compacting text, the turn has one warning; the same event replayed adds none; an ℹ line is still dropped.
- A warning with no running turn is dropped; a warning after a steer lands on the turn that was running.
- A completed turn keeps its warning across the history sync.
