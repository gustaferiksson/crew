# Opening a chat is instant, history loads in pages

User report (2026-11-10): "Opening a chat is quite slow, can we pre-fetch the conversations so it's instant?" (iPhone and Mac), and the biggest chats are slow to open and laggy. The target is Messages and Mail: the conversation is already on screen when it opens, refreshed in place, and older messages load as you scroll up.

## Where the time goes today

Measured 2026-11-10 from the Mac on the same network as the server (`Tests/chat_probe/run.sh open-timing`, read-only GETs on real bots, `session.resume` only on `crew-test`) and in an offscreen `ChatView` host (Xcode 27, M-series Mac):

| Bot | Rows loaded | Bytes | GET (500) | Decode | `Transcript(history:)` | First frame |
| --- | --- | --- | --- | --- | --- | --- |
| Big bot A | 500 (more exist) | 1.6 MB | 112-164 ms | 5-24 ms | 31-82 ms | 32-39 ms |
| Big bot B | 500 (more exist) | 1.7 MB | 107-125 ms | 6-16 ms | 29-90 ms | 105-115 ms |
| Bot C | 178 | 825 KB | 66-88 ms | 3-7 ms | 11-29 ms | not measured |
| Crew Test | 30 | 34 KB | 26-28 ms | 0-2 ms | 8-17 ms | not measured |

`session.resume` takes 17-40 ms (warm or after `session.close`), `session.events.since` 5-6 ms. A `ChatSession` on `crew-test` shows its first row 75-137 ms after it starts. The higher numbers in each range come from a run with an iOS UI test suite busy on the same Mac.

On an iPhone 18 Pro simulator (Debug build, `-snapshot composer-line` with the recorded long replies repeated), building a 490-row transcript takes 73-83 ms and its first layout 145-168 ms; a 105-row page builds in 20-22 ms and lays out in 147-158 ms, so on iOS too the first layout does not depend on the row count.

So a chat opens empty and fills 200-440 ms later on a Mac next to the server, dominated by fetching and building all 500 rows (1.6 MB for the big bots). On an iPhone on cellular or VPN the same 1.6 MB is the part that grows (not measurable from the Mac). The first frame of a 500-row chat is no slower than a 50-row one (the `LazyVStack` lays out only what shows), so rendering is not the dominant cost. While a big chat is open, every roster position change refetches the same 500 rows and rebuilds the transcript on the main thread (30-48 ms each), which is a likely part of the lag. Bots A and B have more than 500 rows, so their oldest messages are unreachable today.

After layer 1, a prefetched chat opens with its cached transcript in the first frame: seeding a `ChatSession` takes under 0.1 ms (real server, `crew-test`), so the open costs only the first frame (Mac about 15-40 ms for a 100-row page, measured on rows decoded without their tool calls so approximate; iOS simulator 147-158 ms on the recorded fixture), against 200-440 ms (Mac) and about 360-430 ms (iOS simulator, same network) before. Both are sums of separately measured parts, not one end-to-end timing, and there are no device numbers. The page itself is fetched in the background: 24-62 ms and 34-561 KB per bot on the real server (bot A 292 KB, bot C 561 KB).

## The change

Two pull requests, the second stacked on the first.

### 1. Prefetch the latest page (this flow's first layer)

- `BotStore`'s preview refresh fetches the latest 100 rows (one page), instead of 20, for up to 10 bots in the order the list shows them (favourites, then the sections in their order; hidden bots excluded), fetched first so the visible rows fill first, and only when the page's read position (`resolved_id` + `message_count`) differs from the bot's, as the preview does today. The preview comes from the same rows. Every other bot keeps the 20-row preview fetch. A prefetch is a read-only REST GET: no `session.resume`, no runtime and no `ChatSession`, so `ChatSessions.status`/`summary`, the Tasks tab and the server's live sessions see nothing new.
- The page is kept as a transcript that starts at the window's first user row that starts a turn (a prompt or a routine notice), skipping a `Message from` reply or a delivery follow-up whose origin may lie before the cut; with no such row it starts at the first user row as before. The 20-row preview uses the same rule. A test over every cut of the recorded histories shows that such a window shows exactly the whole chat's last turns (without the rule, 9 cuts of `bot-thread` showed a relay as a "Message from" row and orphaned follow-ups); a window with no turn-starting row, only an exchange and its follow-up, still shows the relay as a "Message from" row until the attach.
- The page is kept with the read position it came from, in memory and in `Caches/<bundle id>/transcripts/<bot>.json` (the app's own folder: the Mac app is not sandboxed, so plain `Caches` is shared with other apps; not the app-group container; on iOS protected until the first unlock like `bots.json`, so a background launch from a push can read it, and a file it cannot read is skipped, never deleted; a page over 1 MB is not written). A page with no user row (one long tool turn) is not kept (its old file is removed), and the row keeps the server preview. While a bot is working or waiting, its position moves with every step, so it gets the 20-row preview fetch and its page is fetched once it is idle. A fetch whose position is no longer the bot's when it lands is dropped, so overlapping refreshes never write an older page last. At launch the files are read off the main thread and give the chats their content before any network, and the rows their previews when the file's position is still the roster's; a page whose position still matches is not fetched again, so a relaunch refetches only bots that moved. Files are trimmed to 10 (a bot leaving the top 10 keeps its file until an 11th bot needs room, so rank churn does not refetch); a deleted or hidden bot loses its file; sign-out deletes the folder, and a fetch still in flight at sign-out does not write. A page is shown only while its `resolved_id` matches the bot's, so a new chat, a compaction or another server with the same bot name never shows an old page.
- `ChatScreen` shows the cached transcript from its first frame (no empty frame during the iPhone push or the Mac selection change), and opening (`ChatSessions.open`) seeds the new `ChatSession` with it. When the files finish loading after a chat opened at launch (a restored Mac chat window, a cold push tap, Siri), a session that has neither attached nor shown anything takes the seed then. The session then attaches as today (`session.resume`, the full history, `events.since`) and replaces the seed in place: turns keep their ids (row ids), the view holds the end, and older turns appear above. Known limitation: a reader who scrolled up inside the seed before the attach lands (seconds on a slow link) sees what they read move down by the height of the older turns, the same unanchored prepend measured for layer 2 below; it goes away with layer 2's anchor.
- The bot row reads its preview, time and status from a session only once it has attached, so a stale seed never overrides a fresher roster preview.
- A message sent before the session has attached (cached content invites typing) is queued (the usual Queued bubble) and submitted when the attach finishes, after the slash command catalog has loaded so a queued `/command` still runs as a command. If the attach fails, queued text goes back to the draft (a queued attachment stays queued for the next attach), and a later send retries the attach. A queued `/new` keeps the messages queued after it. Card buttons and the shop offer act only once attached: the offer is hidden on a seed, and a card button tapped before the attach gives the error haptic. Today such a send was dropped silently.

### 2. Load history in pages

- Opening (the attach's `load`, `reload`, every catch-up `sync` on a moved read position, `compact`) fetches only the latest page: `GET /api/sessions/{id}/messages?order=latest&limit=100&offset=0`. `ChatSession` keeps the raw rows it has loaded (`HistoryPages`) and merges a refetched latest page by id, so older pages the reader loaded stay; a page that does not reach the loaded rows (more than 100 new rows) replaces them, and a page shorter than 100 rows is the whole chat. A changed session id, Compact Chat and Start New Chat drop the loaded rows.
- Near the top: when one of the first 5 loaded turns becomes visible (`onScrollTargetVisibilityChange` on the turns), the session loads the next older page (`offset` = rows held, so a page can only overlap, never leave a gap; overlapping rows are deduplicated by id). While it loads, a system `ProgressView` ("Loading earlier messages") sits above the first turn, outside the scroll target layout. A failed load turns it into "Couldn't load earlier messages" with Try Again. One load runs at a time; a page that adds no new turn above (a long tool run) loads the next one at once. When a page returns fewer than 100 rows, the start of the chat is reached: the row goes away and the chat is rebuilt from all rows (`Transcript(history:)`), so a chat that starts with a bot-to-bot reply shows it as before.
- The older turns are spliced in front of the shown ones (only turns not already shown, in the same update), so a running last turn, queued and steered prompts, kept commands and failures are never touched. Turn ids are row ids, so every shown turn keeps its id.
- Keeping the reading position: no custom mechanism. `ChatView` already binds `ScrollPosition(idType: Turn.ID.self)` over the turns' `.scrollTargetLayout()`, and SwiftUI keeps the turn it tracks in place when rows are inserted above it. Measured on the Mac host (`TranscriptScroll`, 100 rows of mixed height, then 100 prepended): 1520 pt up 0.2 pt, at rest at the top 0.1 pt (6 of 6), 5 pt and 40 pt below the top 0.1 to 0.25 pt. It fails only while the scroll view is overscrolled past the top (rubber band): 844 to 1304 pt in 5 of 6 runs at -0.75 pt or more, because the scroll view keeps its edge. #277's 753 pt came from a harness with an untyped `ScrollPosition()`, which tracks no id. The tried same-update `scrollTo(id:anchor: .top)` on the previously first turn lands exactly but moves a reader at rest by that turn's offset (64 pt), so it is not used. iOS: `HistoryPagesUITests` (below).
- Page boundary: `HistoryPages.transcript` is `Transcript(window:)` until the start is reached, so a page starts at its first turn-starting user row and a reply or follow-up whose origin is cut off never shows as an orphan or duplicate (#277's every-cut test, now also run as stepwise prepends at page sizes 7, 12, 25 and 40 over every recorded history).
- Search: a hit not in the loaded turns loads up to 4 older pages (500 rows, the old limit) until its turn is found, then centres it as before.
- The rebuild from the loaded rows stays on the main thread as before; a refetch now rebuilds 100 rows plus the pages the reader loaded, instead of 500.
- The prefetch cache holds exactly the latest page, so the seeded transcript and the first page are the same rows. A seeded chat shows no progress row until it has attached.
- `ConversationTranscript` (other conversations) and group rooms keep their own loading.
- Known: a pinned card older than the loaded pages hides its chip until its page is loaded.

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
- Layer 2: `PageWindowTests` pages every recorded history at sizes 7, 12, 25 and 40 and checks each step shows the whole chat's last turns with the shown ones unchanged, and that a refetched latest page keeps older pages unless it leaves a gap; `HistoryPagingTests` drives a `ChatSession` over a stubbed 490-row chat: the open fetches one 100-row page (on main: 500), an older page lands above the shown turns, a catch-up fetches only the latest page and keeps the older ones, a failed load shows the failure, and paging to the start gives the whole history. `HistoryPagesUITests` (iOS, private simulator): an older page landing while the reader sits near the top, and at the top, leaves the row being read in place. Real-server probe `Tests/chat_probe/run.sh pages` (read-only on every bot): pages each chat to its start and compares every step with the whole history.
