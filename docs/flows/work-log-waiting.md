# Waiting dots in the live work log

After a send, the model often thinks for several seconds before its first tool call or text (12 s on `crew-test`), and Hermes sends nothing visible in that time: `thinking.delta` is only the TUI spinner face, and the model rarely streams `reasoning.delta`. The chat showed a faint "Working for 5s" header with nothing under it, which read as stuck. Now three small dots, like Messages' typing indicator, sit where the next work row will land.

## When they show

`Turn.quietSince` is when the live turn last showed something: the turn start with no work yet, the end of the last finished tool or thinking row, or the last note. It is nil (no dots) while a tool is running, a thinking row is streaming, reply text is streaming, or the turn has ended.

- No work yet: dots at once, from the send until the first row or text.
- Between items: dots after 2 s of nothing new (`Turn.quietGap`), so a quick tool batch never flashes them. Recorded timing (`chat.think-turn.v0.22.2.jsonl`): dots 0 to 7.2 s, a 0.1 s tool, nothing for 2 s, dots 9.3 to 15.4 s, then the reply.
- They leave at once when the next row or text arrives (no fade out, so the new row takes their slot without a jump) and fade in over 0.3 s.

## Look

- Three 8 pt circles, 4 pt apart, `.secondary`, at the work rows' leading edge, in a row as tall as a tool row (20 pt line, 6 pt vertical padding). No text, no new chrome.
- A soft wave of opacity (0.3 to 1, 1.2 s). Reduce Motion: the three dots fade together between 1 and 0.6, the same pulse as the "Working for" header.
- VoiceOver: one element labelled "Thinking".
- Light and dark: secondary on the system background, checked in renders.

## Surfaces

- Bot chats on iPhone and Mac: the last live turn's expanded work log. The header is unchanged: "Working for", then `status.update` text or "Preparing <tool>", and Stop.
- Group rooms: the room's "working" turn has no items, so the dots show for the whole turn, which is right since rooms get no live items.
- Turns started by another bot's message stay collapsed under their pulsing "Message from" header, so no dots there unless expanded.
- History, finished, stopped, failed and offline turns: none (not streaming). A reconnect replay rebuilds the turn, and the rule applies again from the replayed items.
- Bot list, push and inspector: unchanged.
