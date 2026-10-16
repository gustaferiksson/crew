# Search messages

The sidebar search field finds words inside chats, not only bot names, the way Messages does: matching conversations first, then matching messages with the hit highlighted. Choosing a message opens that chat scrolled to it, and the message glows briefly so the eye lands on it.

## Server

- `GET /api/sessions/search?q=&profile=&limit=` (FTS5 over every stored message of one profile, prefix-matched per word, hidden sessions included, which is how the Bot Chat is found). It returns one result per compression lineage, the best-ranked (BM25) message of each, never sorted by time. Verified on 0.22.2 against `crew-test`: the Bot Chat comes back with its lineage tip as `session_id`; `snippet` is about 40 tokens with `>>>`/`<<<` around each match and `...` where it was cut; `role` is `user`, `assistant` or `tool`.
- The route also returns id matches and title matches (`role: null`, the session preview as snippet). Those are not message hits and are dropped, otherwise "chat" would list every bot through its "Bot Chat" title.
- When FTS is stale the server falls back to a LIKE scan that returns a raw cut of the message with no markers; the client then emphasises the query words itself. A multi-word query with no AND match is relaxed to OR, and a Latin miss falls back to trigrams, so a hit need not contain every word.
- Kept rows: `assistant` rows (the bot's words) and `user` rows the user typed ("You: "). A user-role row that is a bot-to-bot message shows as "<sender>: <text>". Tool rows, delivery notices (`[IMPORTANT: Background process`), server notices (`[System:`) and hidden widget sends (`<a2ui-action>`) are dropped. Because the server keeps one row per conversation, dropping it drops that conversation from the results; accepted.
- Bot Chat or other conversation: the result's `session_id` or `lineage_root` equals the bot's `canonical_session` `id` or `resolved_id`, else the title is exactly "Bot Chat" (the same rule as the inspector's Other conversations card).
- One request per visible roster bot (hidden bots skipped), at most 4 in flight, `limit=5`, `exclude_sources=subagent,tool` (internal runs Crew never shows). The search starts 300 ms after the last keystroke, needs at least 2 characters (trimmed), and a new keystroke cancels the one in flight.
- Read-only. No crew-push change, no new server state.

## Sidebar (iPhone list, iPad and Mac sidebar)

- Empty query: unchanged list.
- 1 character: unchanged name filter (bots by title, name or preview; rooms by name), no headers.
- 2 or more characters: two sections.
  1. **Conversations**: bots whose title or name matches and rooms whose name matches (no longer the preview, which the Messages section now covers, so a word in the last reply doesn't list the bot twice). Unchanged look, selection, context menus and swipe. Hidden when nothing matches.
  2. **Messages**: one row per hit, newest first (by the date below; undated Bot Chat hits sort by the chat's last activity).
- Message row (same insets, separators and dot gutter as a bot row so the column lines up):
  - The bot's avatar at the bot row size, with its live mood.
  - Line 1: bot title in headline and a trailing date in the bot row's date style. FTS hits carry no message time and the Bot Chat hit can be from any point in its history, so its date is the matching turn's time when that bot's chat is loaded in this launch, else no date (showing the chat's last activity would date a year-old line "10:42"). Other conversations show their last activity, like Mail's thread date.
  - Line 2, only for a hit outside the Bot Chat: "in <conversation title>" in secondary, one line.
  - Snippet, up to 2 lines: secondary text with each matched word in primary and semibold, trimmed in front so the first match is in view. "You: " leads it when `role` is `user`. Markdown markers, check boxes and a2ui fences are removed and line breaks become " · ", the cut points keep their ellipses. A user-role hit cut at the front that ends in "]" is a server notice and is dropped.
- Tapping a row selects that bot (iPhone pushes the chat, iPad and Mac show it in the detail column), exactly like tapping its bot row. Two hits from one bot never share a selection tag; rows are buttons that set the selection. Known gap on Mac: arrow keys from the search field move through bot rows only, not message hits.
- On iPhone, going back from the chat keeps the search text and results, like Messages.
- Searching: the previous results stay on screen while the next query is debounced and sent, and are replaced when the first new reply lands, so typing never blanks the list. With nothing on screen yet, the Messages section shows a small spinner row "Searching…". Later replies slot in by date. Returning to the list with the same query, roster and server does not search again.
- No hits anywhere (no conversation and no message): `ContentUnavailableView.search(text:)` over the list.
- Some bots fail (one profile's store is busy): their hits are missing and a footnote under the section says: Some bots couldn't be searched. All fail: the Messages section shows "Couldn't search messages." in secondary with a Try Again button.
- Offline or signing in: the Messages section shows "Connect to search messages." instead of a spinner; Conversations keeps working from the cached roster. Reconnecting reruns the search.
- Clearing the field or tapping Cancel (iPhone) returns to the normal list; the last opened chat stays open.

## The chat it opens

- **Bot Chat hit:** `BotsView` owns a one-shot jump request (bot, snippet and a fresh id per tap) and hands it to that bot's `ChatScreen` and `ChatView`. The chat scrolls so the matching turn is centred (on screen is enough; a lazy stack may land a row off) and the turn gets a soft tint backdrop (`.tint` at 12 % opacity, 12 pt rounded corners, 8 pt outset) that fades out after 2 seconds. Once jumped, the chat is no longer at the bottom, so the existing follow-the-bottom rule leaves it there until the user scrolls back down or taps Jump to Latest. Matching: the snippet's plain text (markers removed, cut at each `...`, whitespace collapsed) is looked up in each loaded turn's prompt, reply, agent message and work notes, also whitespace collapsed and with markdown left in; the newest turn holding the longest piece wins, else the newest turn containing every matched word.
- History loads after the chat opens, so the jump waits for the turn to appear; if it never does (the hit is older than the 500 loaded rows, or it was in a tool row that isn't shown), the chat opens at the bottom like any other open. No error is shown: the chat itself is the answer.
- The jump is one-shot: new replies, scrolling or reopening the bot do not jump again. Choosing another hit in the same open chat jumps again.
- **Other conversation hit:** selects the bot (its chat opens underneath, as from the inspector) and presents the read-only conversation sheet (the same `ConversationTranscript` the inspector's Other conversations card opens, now presented by `BotsView` too) scrolled to the matching turn with the same tint. Cron routine runs count as other conversations ("in <routine name>").
- The bot is marked seen as with any open; unread, time, Working and preview on its row are unchanged.

## Every direction and other surfaces

- **Sender only:** search is a reader feature. Nothing is sent, so no bot sees anything and no reply comes back.
- **Bot list rows, favourites, push, inspector, group rooms:** unchanged. Rooms have no searchable messages of their own (`groups.log` is not indexed), so they match by name only. If a member profile's room session comes back as a hit it opens read-only like any other conversation, not the room (known gap; routing it to `group:<id>` needs the session to name its room).
- **Mac:** the sidebar search field keeps its text while you read the chat, like Messages, so you can step through hits. No new Find shortcut in this change.

## States

- Long titles: one line, truncated. Long snippets: 2 lines.
- Many hits: at most 5 per bot; the list scrolls.
- Deleted bot while results show: its hits disappear with the roster.
- Query with FTS syntax (quotes, `OR`, `*`): sent as typed; the server sanitises it and a query it can't run returns no hits, not an error.
- Large Dynamic Type: rows grow like bot rows.
- Light and dark: system styles only; the highlight uses the tint.
- VoiceOver: each message row reads "<bot title>, <snippet>, <date>" as one button; "in <title>" is included for other conversations.

## Tests

- Unit: decoding the recorded `sessions.search` replies (`Tests/fixtures/sessions.search.*.v0.22.2.json`: a Bot Chat user hit, other-conversation assistant hits with markdown and a fence, and a tool-row hit), dropping title-lane, tool, notice and delivery rows, the agent-message sender prefix, markerless highlighting, snippet flattening and highlighting (markers, ellipses, newlines, a fence, "You:" prefix), matching a snippet to a turn on `ChatFixture.history` and on a real recorded Bot Chat history, Bot Chat vs other conversation classification, ordering and the 2-character rule.
- UI (iPhone simulator, `sidebar-search` fixture with canned hits, no network): typing a word shows the Messages section with the hit; tapping it opens the chat with the matching turn on screen.
- Renders: `sidebar-search` on iPhone, light and dark, and the opened chat with the highlight.
- Real server: the probe search above on `crew-test` (read-only).

## Not in scope

- A message-level jump for hits older than the loaded 500 rows (would need paging history backwards).
- Search inside one chat (Cmd-F in the transcript).
- Spotlight indexing.
