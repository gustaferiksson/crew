# Waiting dots in the live work log

After a send, the model often thinks for several seconds before its first tool call or text (12 s on `crew-test`), and Hermes sends nothing visible in that time: `thinking.delta` is only the TUI spinner face, and the model rarely streams `reasoning.delta`. The chat showed a faint "Working for 5s" header with nothing under it, which read as stuck. Now three small dots, like Messages' typing indicator, sit where the next work row will land.

## When they show

`Turn.updatedAt` is when the live turn last changed on screen (any tool, thinking, note or text event, stamped when Crew applied it, so live and replayed events use the same clock). `Turn.quietSince` is that time (or the turn start when nothing has arrived yet), and nil (no dots) while a tool is running (its row has a spinner), while reply text is showing, or once the turn has ended.

- No work yet: dots at once, from the send until the first row or text.
- Between items: dots after 2 s of nothing new (`Turn.quietGap`), so a quick tool batch never flashes them. Recorded timing (`chat.think-turn.v0.22.2.jsonl`): dots 0 to 7.2 s, a 0.1 s tool, nothing for 2 s, dots 9.3 to 15.4 s, then the reply.
- They leave at once when the next row or text arrives (no fade out, so the new row takes their slot without a jump) and fade in over 0.3 s.

## Look

- Three 8 pt circles (scaled with Dynamic Type like `.subheadline`), half a dot apart, `.secondary`, at the work rows' leading edge, in a row exactly as tall as a tool row (one `.subheadline` line plus 6 pt vertical padding), so the next row takes the slot without a jump. No text, no new chrome.
- A soft wave of opacity (0.3 to 0.8, 1.2 s, at most 30 updates a second), so the dots stay quieter than text. Reduce Motion: the three dots fade together between 1 and 0.6, the same pulse as the "Working for" header.
- VoiceOver: one element labelled "Thinking".
- Light and dark: secondary on the system background, checked in renders.

## Surfaces

- Bot chats on iPhone and Mac: the last live turn's expanded work log. The header is unchanged: "Working for", then `status.update` text or "Preparing <tool>", and Stop.
- Group rooms: the room's "working" turn has no items, so the dots show for the whole turn, which is right since rooms get no live items.
- Turns started by another bot's message: no dots, even when expanded; their pulsing "Message from" header stands in.
- History, finished, stopped and failed turns: none (not streaming). A reconnect replay rebuilds the turn and stamps the replayed items with the replay time, so the rule applies again from there.
- Offline: a live turn stays streaming while Crew reconnects (as the "Working for" header does today), so the dots keep going until the reconnect settles the turn.
- Bot list, push and inspector: unchanged.
