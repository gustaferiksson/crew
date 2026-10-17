# Compact live work log

Two complaints from use: after a send, a faint "Working for 5s" header sat over nothing for 10 s or more, which read as stuck; and the work log was forced open while a turn ran, then snapped shut to "Worked for" when it ended, so the messages jumped. Now the live turn shows one header line: "Working for 12s ••• ›", which becomes "Worked for 15s ›" in the same place.

## Header

- Live: "Working for Xs" (digits monospaced so nothing after it jiggles each second), three small dots, then the existing `status.update` text or "Preparing <tool>" in tertiary, then the chevron (only once there is something to expand; the time never truncates, the activity text does). On iPhone the Stop button stays at the trailing end.
- The dots show from the send until reply text starts streaming; a recorded crew-test turn (`chat.think-turn.v0.22.2.jsonl`) shows them for 15.3 s, through a silent 7 s, a tool call and another silent 8 s. Once text streams the reply itself shows progress.
- The header text no longer pulses; the dots carry the "alive" signal, so two animations never drift side by side.
- Finished: "Worked for Xs ›", same font and height, so the transition is a text change, not a layout change.
- VoiceOver reads the header with "Expanded" or "Collapsed" once it has rows.
- Tapping the header expands the full log (thinking, notes, tool rows) both while live and after; the expansion is kept per turn, so a log the user opened during the turn stays open when it ends. Nothing opens or closes on its own.

## Dots

- Three 4 pt circles (scaled with Dynamic Type like `.subheadline`), 2 pt apart, `.secondary`, inline after the time, so they sit on the text's line like an ellipsis.
- A soft wave of opacity (0.3 to 0.8, 1.2 s, at most 30 updates a second). Reduce Motion: the three dots fade together between 1 and 0.6, no wave.
- Hidden from VoiceOver: the header already reads "Working for Xs".

## Surfaces and states

- Bot chats on iPhone and Mac, light and dark: the last live turn's header.
- Approval and question cards, Stop, Steer and Queue are unchanged; a steer still splits the turn (the old turn becomes "Worked for", the steer turn starts its own "Working for"), and the steer's answer still shows as full text under its bubble.
- Mid-turn commentary (`message.interim`) and thinking rows are now inside the collapsed log while live, one tap away, instead of showing under the header. Text the bot streamed before a tool call is sealed into a note there too, so it leaves the screen when the tool starts and the dots return (the user asked for the header alone; showing the latest note under it is the follow-up if this feels lossy).
- A turn with no work at all (a plain reply) has no log, so its header goes away when it ends, as before, and the reply moves up by one line.
- A steer starts a new turn, which starts collapsed even if the user had opened the previous one.
- Turns from another bot keep their pulsing "Message from" header, collapsed as before.
- Group rooms: the working turn shows the same header with dots.
- Stopped and failed turns: "Worked for Xs ›" with the "Stopped" or error line under it, as before.
- Offline: a live turn stays streaming while Crew reconnects (as before), so the header keeps counting until the reconnect settles the turn.
- Bot list, push and inspector: unchanged.
