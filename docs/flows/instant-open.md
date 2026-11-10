# Opening a chat is instant, history loads in pages

User report (2026-11-10): "Opening a chat is quite slow, can we pre-fetch the conversations so it's instant?" (iPhone and Mac), and big chats (Marlow, Emil) are slow to open and laggy. The target is Messages and Mail: the conversation is already on screen when it opens, refreshed in place, and older messages load as you scroll up.

## Where the time goes today

Measured 2026-11-10 from the Mac on the same network as the server (`Tests/chat_probe/run.sh open-timing`, read-only GETs on real bots, `session.resume` only on `crew-test`) and in an offscreen `ChatView` host (Xcode 27, M-series Mac):

| Bot | Rows loaded | Bytes | GET (500) | Decode | `Transcript(history:)` | First frame |
| --- | --- | --- | --- | --- | --- | --- |
| Marlow | 500 (more exist) | 1.6 MB | 112-164 ms | 5-24 ms | 31-82 ms | 32-39 ms |
| Vera | 500 (more exist) | 1.7 MB | 107-125 ms | 6-16 ms | 29-90 ms | 105-115 ms |
| Emil | 178 | 825 KB | 66-88 ms | 3-7 ms | 11-29 ms | not measured |
| Crew Test | 30 | 34 KB | 26-28 ms | 0-2 ms | 8-17 ms | not measured |

`session.resume` takes 17-40 ms (warm or after `session.close`), `session.events.since` 5-6 ms. A `ChatSession` on `crew-test` shows its first row 75-137 ms after it starts. The higher numbers in each range come from a run with an iOS UI test suite busy on the same Mac.

On an iPhone 18 Pro simulator (Debug build, `-snapshot composer-line` with the recorded long replies repeated), building a 490-row transcript takes 73-83 ms and its first layout 145-168 ms; a 105-row page builds in 20-22 ms and lays out in 147-158 ms, so on iOS too the first layout does not depend on the row count.

So a chat opens empty and fills 200-440 ms later on a Mac next to the server, dominated by fetching and building all 500 rows (1.6 MB for the big bots). On an iPhone on cellular or VPN the same 1.6 MB is the part that grows (not measurable from the Mac). The first frame of a 500-row chat is no slower than a 50-row one (the `LazyVStack` lays out only what shows), so rendering is not the dominant cost. While a big chat is open, every roster position change refetches the same 500 rows and rebuilds the transcript on the main thread (30-48 ms each), which is a likely part of the lag. Marlow and Vera have more than 500 rows, so their oldest messages are unreachable today.

After layer 1, a prefetched chat opens with its cached transcript in the first frame: seeding a `ChatSession` takes under 0.1 ms (real server, `crew-test`), so the open costs only the first frame (Mac 15-40 ms for a 100-row page, iOS simulator 147-158 ms), against 200-440 ms (Mac) and about 360-430 ms (iOS simulator, same network) before. The page itself is fetched in the background: 24-62 ms and 34-561 KB per bot on the real server (Marlow 292 KB, Emil 561 KB).

## The change

Two pull requests, the second stacked on the first.

### 1. Prefetch the latest page (this flow's first layer)

- `BotStore`'s preview refresh fetches the latest 100 rows (one page), instead of 20, for up to 10 bots in the order the list shows them (favourites first, then waiting, working, unread and most recent activity; hidden bots excluded), fetched first so the visible rows fill first, and only when the page's read position (`resolved_id` + `message_count`) differs from the bot's, as the preview does today. The preview comes from the same rows. Every other bot keeps the 20-row preview fetch. A prefetch is a read-only REST GET: no `session.resume`, no runtime and no `ChatSession`, so `ChatSessions.status`/`summary`, the Tasks tab and the server's live sessions see nothing new.
- The page is kept as a transcript (rows from the first user row on, the preview's window rule; a test over every cut of the recorded histories shows a window with a user-started prompt in it shows exactly the whole chat's last turns, while a window with none, only an exchange and its follow-up, shows the relay as a "Message from" row until the attach, as the agent-messages spec already documents for the preview) with the read position it came from, in memory and in `Caches/transcripts/<bot>.json` (the app's own Caches, not the app-group container; complete file protection on iOS; a page over 1 MB is not written). A page with no user row (one long tool turn) is not kept, and the row keeps the server preview. At launch the files are read off the main thread and give the rows their previews and the chats their content before any network; a page whose position still matches is not fetched again, so a relaunch refetches only bots that moved. Files are trimmed to 10 (a bot leaving the top 10 keeps its file until an 11th bot needs room, so rank churn does not refetch); a deleted or hidden bot loses its file; sign-out deletes the folder, and a fetch still in flight at sign-out does not write. A page is shown only while its `resolved_id` matches the bot's, so a new chat, a compaction or another server with the same bot name never shows an old page.
- `ChatScreen` shows the cached transcript from its first frame (no empty frame during the iPhone push or the Mac selection change), and opening (`ChatSessions.open`) seeds the new `ChatSession` with it. The session then attaches as today (`session.resume`, the full history, `events.since`) and replaces the seed in place: turns keep their ids (row ids), the view holds the end, and older turns appear above.
- The bot row reads its preview, time and status from a session only once it has attached, so a stale seed never overrides a fresher roster preview.
- A message sent before the session has attached (cached content invites typing) is queued (the usual Queued bubble) and submitted when the attach finishes, after the slash command catalog has loaded so a queued `/command` still runs as a command. If the attach fails, queued messages go back to the draft. Today such a send was dropped silently.

### 2. Load history in pages (stacked)

- Opening (and every catch-up refetch, `load`, `sync`, `compact`, `reload`) fetches only the latest page: `GET /api/sessions/{id}/messages?order=latest&limit=100&offset=0`. Rows are merged by id with what is already loaded, so older pages the user loaded stay. A refetch whose page does not reach the loaded rows (more than 100 new rows) replaces them.
- Scrolling near the top of the transcript shows a small progress row and loads the next older page (`offset` = rows loaded). Turns are prepended; the row the reader was looking at stays where it is (no jump), like Messages. When a page returns fewer rows than asked, the start of the chat is reached and the row goes away.
- Page boundary: a page can start inside a turn (tool rows before their prompt), or after a `message_agent` call whose reply or delivery follow-up is in the page. The transcript starts at the page's first user-started row, and when a delivery follow-up or a `Message from` reply in the window has its origin before that cut, one more older page is loaded before it shows, so a page boundary never shows a relay as an extra "Message from" row or a duplicate follow-up. Rule chosen from a test over every cut of the recorded scenario histories.
- Search: a hit older than the loaded rows loads older pages until its turn is found (at most 500 rows, today's limit), then scrolls to it as today.
- The prefetch cache holds exactly the latest page, so the seeded transcript and the first page are the same rows.
- Layer 2 details from the spec review, settled in its own PR: a `resolved_id` change (Start New Chat, compaction) replaces all rows and paging state; one older-page load in flight per session, merged into the current rows at completion and never touching a running last turn; a failed older-page load turns the progress row into "Couldn't load earlier messages" with Retry; a pinned card older than the first page loads pages until present (or keeps the chip); `ConversationTranscript` (other conversations) stays on its 500-row load; merges build off the main thread.

## Surfaces and directions

- **Bot chat, iPhone (`ChatScreen`, pushed from the list, a push tap, search or Siri) and Mac (main window column and `BotChatWindow`):** opens with the cached page in the first frame, at the end; the refresh adds older turns above without moving the end.
- **Bot list (preview, time, status, unread):** preview and time come from the same rows as before (now 100 instead of 20 for the first 10 bots, so fewer window cuts); status and unread are untouched (no `ChatSession` is created by a prefetch, so `ChatSessions.status`/`summary` see no new sessions). Opening still marks the bot seen (`markSeen` on appear), exactly as today.
- **Sender:** typing and sending right after opening works: before the attach the prompt is queued, then submitted.
- **Receiver (replies back):** a reply that arrives while the chat is closed moves the position, the prefetch refetches the page and the preview; opening shows it. While open, the session catches up as today (`sync`).
- **Push:** a push tap opens the cached page at once; a cold app's page predates the pushed reply (prefetch runs only in the foreground), so the reply lands at the end when the attach finishes while the view holds the end. crew-push is unchanged.
- **Inspector (Tasks tab):** unchanged; it reads `ChatSession.todos`, which still come from the attach.
- **Other conversations, group rooms:** unchanged (their own sessions, no cache).
- **Light and dark:** no visual change in layer 1; layer 2 adds a system `ProgressView` row at the top while an older page loads.

## States

- **Offline (cache present):** the chat opens with the cached page, readable; the offline line and disabled composer show as today. A queued send waits for the attach after reconnect.
- **Offline (no cache):** as today, empty until connected.
- **Stale cache** (position moved since the page was written, for example the app was closed): the cached page shows first, then the attach replaces it with the current rows in place; the reader stays at the end.
- **A reply arriving while cached (chat closed):** the roster position moves, the prefetch refetches the page within one roster refresh (about 2 s in the foreground), the preview updates; opening shows the reply.
- **A reply arriving during the attach:** the attach's own fetch and `events.since` replay bring it in, as today.
- **Bot deleted:** its cache file is removed with the roster change; a deleted bot's chat cannot be opened.
- **New chat or compaction (`resolved_id` changed):** the old page no longer matches and is not shown; the next prefetch writes the new one.
- **Many bots:** only the first 10 ranked bots are prefetched (one 100-row GET each on position change); the rest keep the 20-row preview fetch and open as today (empty, then filled).
- **Long content:** a page is 100 rows whatever their size (the heaviest bot's page is about 330 KB).
- **Empty chat:** no cache file (no rows), opens with the empty state as today.
- **Signed out:** the cache folder is deleted with `bots.json`.
- **Error fetching a page:** the file stays as it was and the position is retried on the next roster, as the preview does today.

## Tests

- Layer 1: a `ChatSession` seeded from a cached page shows its visible turns before any network; the full history then replaces it keeping the seeded turns' ids; a send before the attach is queued and submitted after it (fails on main: dropped); `BotStore` prefetches 100 rows only for the first 10 ranked, non-hidden bots, writes and evicts files, and never creates a `ChatSession`. Real-server probe on `crew-test`: open timing before and after.
- Layer 2: windowed `visible` against the suffix of the full `visible` over every cut of the recorded scenario histories; merge of a refetched page with loaded older pages; prepend without moving the reader in `TranscriptScrollTests`'s harness and one iOS UI test on a private simulator; search hit older than the first page.
