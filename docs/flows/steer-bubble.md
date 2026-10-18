# A mid-turn steer always shows its words

Reported on the Mac (v0.1.24): between a turn ("Worked for 33s") and the short run after it ("Worked for 4s"), Crew drew a blue user bubble at full width with no text.

## What the row was

The user's own steer, typed in Crew while the bot was working. Hermes stores it as `role: user`, `display_kind: steer`, with `content` wrapped in its model-facing marker (`[OUT-OF-BAND USER MESSAGE — …]\n<text>\n[/OUT-OF-BAND USER MESSAGE]`), and `/api/sessions/{id}/messages` adds `display_content` with only the user's words. It is not a hidden or system row, an attachment or whitespace, so the right result is the ordinary blue bubble with the user's text, as Messages shows every message the user sent. `Tests/fixtures/chat.steer-shop.history.json` is that turn (rows 134 to 154) with every text replaced by neutral stand-ins and the markers, kinds, ids, tool names and timing kept.

`Transcript(history:)` on the real rows already gives the steer turn its text (`SteerShopScenarioTests`), so the history path and the model were never empty. The real steer was 74 characters, which at the Mac's body size measures about 520 pt, so a bubble at the 560 pt maximum is its own width: the text was laid out but not drawn. The user saw it live, right after sending the steer, so the suspect is the flip from Waiting (outlined bubble, blue text) to taken (filled bubble, white text) under the same view identity on the Mac, where the bubble's `Text` has both a custom `textRenderer` and `.textSelection(.enabled)`. The Mac UI test below must fail on main before the fix lands, or the cause is not proven.

## Rule

- A steer is a user bubble with the user's words: Waiting is the outlined bubble with "Waiting" under it; once the agent takes it the bubble fills and the text turns white, in place, with no gap and no crossfade (like Messages' Send Later bubble turning solid). An implementer must not add a transition here: two overlapping states are what this fix removes.
- The bubble's text is always drawn in the colour of its current state. The text and its bubble change together on take, on the history sync after the reply (where `adoptIDs` keeps the local id when the texts match, and the view is recreated under the row id when they don't, for example two steers joined into one bubble), and on a cold open.
- On the Mac a taken steer stays selectable, with a readable selection on the blue fill, and keeps Copy and Share in its context menu.
- An empty bubble is never drawn: a turn whose prompt has no text and no attachments shows no bubble (already `TurnView`'s rule, now asserted for steer history too).
- Hermes' steer marker never reaches a surface. Transcript, preview and the inspector's other conversations use `display_content`; when a row lacks it, Crew strips the marker from `content` itself, with the same rule search uses on snippets (the opening line, cut or whole, and the closing tag). Search strips before its hidden-row filters run. A hit whose match lies only in the marker's words is dropped, since the user never wrote them.

## Surfaces and states

- Transcript, Mac and iPhone, light and dark: Waiting (outlined), taken (filled, white text, the run splits there with its own "Worked for"), after the reply and the history sync (unchanged), after reopening the chat (same). A second steer before the first is taken joins it in one bubble (unchanged, `takeSteers`). A long steer wraps inside the bubble at 75 % of the column (560 pt max), like any message.
- Separate Mac chat window (#74): same `ChatView`, same result in both windows.
- Other device (receiver): the steer never passes through Waiting there; it arrives with the reply through the history sync as a filled bubble between the two runs. The steer row bumps `message_count`, but unread follows the reply as before (a bot is unread when its count moves past the read marker and the chat is not open), so the steer adds no extra notification or dot.
- Inspector: the Conversations sheet renders sessions through `Transcript(history:)`, so a steer there is the same filled bubble from the history path.
- Bot list row: preview is the reply after the steer; while the steer turn runs with no reply yet, the preview is the steer text; time is the reply's (or the steer's) time. Status Working while the run continues. Unread unchanged (counts messages). Before the history fetch the row shows the server's `canonical_session.preview`, which is the session's opening message, never a steer.
- Accessibility: VoiceOver reads the bubble as the user's words only, and "Waiting" disappears on take. White on the blue gradient is the existing sent-bubble contrast; Dynamic Type wraps inside the bubble like any message.
- Search: a steer match reads "You: <words>" with the query highlighted, never the marker; opening it scrolls to the steer turn.
- Push: crew-push sends the reply as usual; the steer row is a user row and sends nothing (no plugin change).
- Stopped before take: the steer goes back to the draft (unchanged). Stopped after the agent took it but before its next model call: the interrupted `message.complete` turns it into a filled steer turn (unchanged, `stoppingKeepsASteerTheAgentAlreadyTook`). Error from `session.steer`: the bubble is removed and the text returns to the draft with the error (unchanged). Offline: Steer is disabled with the composer (unchanged). Empty steer: Send is disabled for an empty field, so none is sent.

## Verification

- `SteerShopScenarioTests` replays the fixture: the three turns and their bubbles, no empty or marker bubble, the preview, the same rows with `display_content` removed from the steer (transcript and preview still show the words), a live steer taken and synced against the same rows keeps its text and id, and two joined steers whose synced text differs take the row id and keep their text.
- UI tests send a steer in the `composer-running` fixture and wait until it is taken, then measure white text pixels inside the bubble's screenshot: `ChatSendScrollUITests.testATakenSteerKeepsItsTextVisibleInTheBubble` (iPhone) and `SteerBubbleUITests` (Mac, light and dark, CI only).
- `MessageSearchTests`: a cut and a whole steer snippet read "You: <words>" (the whole one also proves stripping runs before the cut-notice filter), a hit matching only marker words is dropped, and the snippet opens the steer turn.
- Reviewer pass on the Mac build: select text in a taken steer, then right-click and check Copy and Share.
- Renders: `chat-steer-taken` now reaches its state through a live take (wait, then the agent takes it), and a history steer on a cold open (`chat-steer-history`), Mac and iPhone, light and dark.
- Real server, only on `crew-test` (no other profile): send a test prompt, steer it mid-turn, let it be taken, then check the history rows (`display_kind`, `display_content`), the sync, a reopen, a search for a steer word, and that `canonical_session.preview` is the opening message.
