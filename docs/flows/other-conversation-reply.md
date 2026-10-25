# Reply in other conversations (#117)

Hermes lets any of a bot's sessions continue (cron runs, other apps, older chats). The Other Conversations sheet was read-only; it now has the normal composer so the user can reply in that session. Nothing else changes: no new list features, no push changes.

## Model

The sheet is the same `ChatView` as the Bot Chat, driven by its own `ChatSession` that resumes the opened stored session (`session.resume`, then `prompt.submit` on its runtime id). Like Messages opening an older thread: same transcript, same composer, the reply streams in place.

## Surfaces

- **Sheet (iPhone and Mac):** title is the conversation title (Untitled when none) in the principal slot; Done closes it. Composer placeholder "Message <bot>". Steer, queue, stop, attachments, dictation, mentions, approvals, questions and payment cards work as in the Bot Chat.
- **Opened from:** the inspector's Other Conversations card and a message-search hit outside the Bot Chat (which still scrolls to and tints the matching turn).
- **Bot list:** unchanged. The sheet's session is not the bot's Bot Chat, so the row's preview, time, status and unread do not follow replies sent here.
- **Bot Chat:** unchanged; the reply lands only in the opened session (probe-checked).
- **Push:** unchanged. crew-push only notifies for the Bot Chat and cron runs, so a reply in a routine's conversation may also arrive as a routine banner when that device has routine pushes on; accepted, no suppression.
- **Light/dark:** system colours, see renders `other-conversation`.

## States

- Loading: a spinner until the session resumes.
- Error: "Couldn't Load Conversation" with Hermes' message when the resume fails; a failed send shows the turn's error line like the Bot Chat.
- Offline: after 2 s away from connected the composer shows its offline line (same rule as the Bot Chat); reconnecting resumes the session.
- Long content: the transcript scrolls with the jump arrow; the title truncates to one line.
- Draft: lives while the sheet is open; a steer that fails returns its text to the draft.

## Verification

- `Tests/chat_probe/run.sh other` on `crew-test`: resumes a cron conversation, sends "Reply with exactly: other-ok", the reply streams, lands in that session's history, the Bot Chat row count is unchanged and the row keeps its title and source.
- Renders `./snapshot.sh both other-conversation`.
