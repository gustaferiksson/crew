# Bot-to-bot messages

A bot (the sender) calls `message_agent`; the other bot (the target) answers in its own Bot Chat; a delivery process carries the reply back to the sender. Hermes stores each step as ordinary rows, so Crew reads the shape from the rows (`Transcript.visible`).

## Target's chat (the bot that was messaged)

- Each exchange started by another bot is one collapsed row in the work-log style: the sender's 16 pt avatar (only when the handle is in the bot list; a relayed or deleted bot shows just the name), "Message from <sender>" with the name from the message itself, a chevron. Like Messages' grouped system rows, it says something happened without competing with the user's own conversation. It is a plain button labelled by its text, like the work-log header, so VoiceOver, Dynamic Type (it wraps) and the Mac keyboard behave the same.
- Expanded, it lists the incoming message, the bot's thinking and tool rows (the `message_agent` reply call included), and the bot's reply, all as secondary work-log note and tool rows, the incoming message first as a quote. The later delivery follow-up turn (the `[IMPORTANT: Background process …` row and the bot's acknowledgement) folds into the same row, so one exchange is one row. It lands seconds after the exchange; if the user has written in between, the follow-up still folds into the row above, which is the honest place for it.
- While the exchange or its follow-up runs, the title pulses like "Working for" does; unlike the work log it stays collapsed (its own expanded state, not forced open while live) and can be opened. The composer shows the running state, and a message the user sends while the last turn is an agent message or a delivery follow-up (`agentMessage` or `delivery` set) is queued until the turn ends, never steered into a reply addressed to another bot.
- Several exchanges are several rows, in order, between the user's own turns.

## Sender's chat (the bot whose user asked for the message)

- Unchanged from #31: the user's prompt and the bot's "queued" line, then the one-line relay turn ("@test-bot replied: …") when the delivery lands. The reply arriving as `Message from <target>` is a reply to this chat's own `message_agent` call and stays hidden, as does the raw delivery notice.
- Rule: each queued `message_agent` call (its result has a `process_id`) to @handle in a user-started turn consumes the next `Message from …(@handle)` turn as its reply (hidden); any other `Message from` turn, such as a second unprompted one, is an exchange and shows as a collapsed row.

## Bot list, push, other surfaces

- Preview: the last visible turn, so a target whose latest activity is an exchange reads "Message from Crew Test", matching its time label. The sender reads the relay line. Both on iPhone and Mac, from the open `ChatSession` or from `BotStore`'s 20-row fetch.
- Time and unread: unchanged (`last_active`, `message_count`); now they always point at something visible.
- Working: shown only for `working` and `waiting` from `session.active_list`. During an exchange the server reports the target `working` and it is; the collapsed row with its pulsing title is what the badge refers to. `starting` (an agent build after a resume, no turn) is not Working.
- Push: unchanged, crew-push 0.3.1 sends no reply or failure push for agent-initiated turns. The local "Replied" alert (push off) still fires on the unread edge, as before; it now matches a visible row, and muting it would need the preview fetch before the alert, so it stays a known gap.
- Inspector: no change.

## States

- Empty chat with only exchanges: the rows are the transcript; no empty state.
- Long message or reply: the expanded rows wrap like work-log notes; the collapsed row is one line that wraps only at large Dynamic Type sizes.
- Failed or interrupted exchange: the row keeps its title; the failure shows under the turn as for any turn.
- Offline: rows render from the loaded transcript; nothing new.
- Window cut (the 20-row preview fetch starts mid-exchange): a delivery follow-up without its origin is hidden unless a user-started turn is loaded, as before; the preview then falls back to the last visible turn. Only the first rows of a 20-row window can be such an orphan, so a newer exchange in the window still sets the preview.
- Light and dark: system secondary styles only.
