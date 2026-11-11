# Context usage ring and sheet (#288)

How full the bot's session context is, modelled on Claude Code's Usage sheet.

## Data (Hermes 0.23.0, recorded on crew-test in `Tests/fixtures/usage`)

- `Usage.context_used` / `context_max` (and `context_percent`, `context_source`) ride on `session.resume`/`session.create` `info.usage`, the `session.info` event, `session.usage` ticks and `message.complete.usage`. crew-test reports 21,971 of 500,000 (Codex cap) after a turn.
- Hermes omits all context fields until a prompt has run in the runtime (`agent/context_breakdown.py::context_usage_fields` returns `{}` without both numbers).
- `session.context_breakdown {session_id}` returns estimated `categories [{id, label, color, tokens}]` (system prompt, tool definitions, rules, skills, MCP, subagents, memory, conversation; zero-token ones dropped) plus its own `context_used`, and `[]` when no agent is resident. The estimates sum past `context_used` (30,827 vs 23,453 on crew-test), so they are shown as "~" rows, not as segments of the bar.
- Hermes auto-compacts at `compression.threshold`, 0.50 of the window by default.

## Surfaces

- Chat toolbar (Bot Chat, iPhone navigation bar and Mac main window and chat window): a 17 pt ring button before Chat Options, filled clockwise from 12 o'clock with used / window, monochrome (primary on a tertiary track) in light and dark. VoiceOver "Context, 28% used"; Mac help tag "Context: 28% used". The ring shares the trailing glass group with Chat Options, so the toolbar keeps two trailing items.
- Tapping it opens the Context sheet from `ChatScreen` (the screen container), never from a row: header "277.7K of 1M tokens", a progress bar and "28% used", all from the same usage value as the ring; an "Estimated Breakdown" section with Hermes' categories (`~4.7K`) and Free Space (window minus used) when Hermes has a breakdown; Done closes it. Medium and large detents on iPhone, a sheet on the Mac.
- Compact: at 40% or more (under the 50% default auto-compaction, so it can show before Hermes acts) the sheet gets a "Compact Chat…" button. It closes the sheet and raises the existing "Compact This Chat?" confirmation and "Chat Compacted" alert (`docs/flows/bot-chat-new-compact.md`); hidden while offline, mid-turn or before the chat attaches, like the menu item.

## States

- No window known (fresh chat, no turn yet, or a server that reports none): no ring at all, never a guessed size. The first completed turn brings it.
- Live: the ring and an open sheet follow every `message.complete`, `session.info` and `session.usage` that carries context fields; a payload without them never clears a known value. The sheet refetches the breakdown whenever usage changes.
- After Compact Chat Crew reads `session.context_breakdown`'s `context_used` once: the recorded compaction emits no `session.info`, and `session.usage` omits the context fields until the next turn (both replies in `Tests/fixtures/usage/*.after-compact.v0.23.0.json`).
- Start New Chat clears the ring until the new chat's first turn.
- Breakdown error or empty: the sheet shows used of total only.
- Long content: the sheet is a grouped Form, rows wrap; numbers use the locale's compact notation ("462,3K" in Swedish).
- Offline: the ring keeps the last value; the Compact button hides.
- Push, bot list rows and rooms: unchanged.
