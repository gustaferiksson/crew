# Start a new Bot Chat, or compact it (#115)

A long Bot Chat only grows. The chat's toolbar gets a Chat Options menu (ellipsis, trailing: iPhone navigation bar, Mac main window and chat window toolbar) with two items, each behind a confirmation dialog. Bot list menus are untouched.

## Compact Chat…

- Dialog "Compact This Chat?": "<Bot> replaces older messages in its context with a summary, so long chats stay fast and focused." Buttons Compact, Cancel.
- Calls `session.compress {session_id: <runtime id>}` (verified on Hermes 0.22.5), then reloads the transcript from REST history. An alert "Chat Compacted" shows Hermes' own headline (for example "No changes from compression: 4 messages").
- Bot row: `message_count` may drop in place; the existing count-drop rule (PLAN.md, #52) keeps it read.

## Start New Chat…

- Dialog "Start a New Chat?": "This chat moves to Other Conversations in <Bot>'s info, and <Bot> starts fresh. Its memory and skills stay." Buttons Start New Chat, Cancel.
- Crew reads the Bot Chat's `runtime_revision` (`GET /api/sessions/{id}`) and sends one fenced `PATCH /api/sessions/{id}` with `title: "Bot Chat until <date>"`, `archived: true`, `hidden: false`, `request_id`, `expected_revision`. The retitle is required: Hermes finds the Bot Chat by exact title even when archived, and falls back to `Bot Chat #N` rows, so neither archiving alone nor a numbered title frees it.
- The chat then empties and re-resolves through the normal open path (`session.create` + `session.title "Bot Chat"`); the roster reloads so the bot row's preview, time and read marker follow the new chat (it is marked read while open).
- Other Conversations now asks for `archived=include`, so the old chat is listed there under its new title and opens as before.

## States

- Disabled: offline, chat not attached yet, empty chat, or the bot is working (no compaction or retirement mid-turn).
- Error: an alert "Couldn't Compact Chat" / "Couldn't Start New Chat" with the server's reason (e.g. a revision conflict); nothing changes on a failed PATCH.
- Long content: titles and messages are system dialogs and wrap; light and dark are system styles.
- Push: unchanged; replies in the new chat push as Bot Chat replies.

## Known limitation: routines

On Hermes 0.22.5 a Bot Chat created by a client (`session.create`, source `tui`) refuses `deliver: bot-chat` hand-offs with `not_found` (already true for every Crew-created Bot Chat, see `routine-delivery.md`). Verified on throwaway `crew-test-*` bots: when no Bot Chat exists, the cron delivery mints a local one that accepts both Crew prompts and later deliveries, but a client cannot mint that kind (`session.create {source: "local"}` is displaced by the next delivery as `Bot Chat (local <id>)`). So a fresh chat from Start New Chat behaves like today's Crew-created chats; fixing it needs a Hermes-side mint.
