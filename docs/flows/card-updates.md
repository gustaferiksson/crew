# Card updates: the old turn points down, the new card says Updated

Skill v7 (#227, PR #238) tells bots to re-send a card under the same `surfaceId` when the user refines it ("make it for 6"), and to send an update-only block (`updateComponents` / `updateDataModel`, no `createSurface`) for small state changes ("tick off the onion"). Crew already moves a re-created card to its newest block and changes an updated card in place, but says nothing about it:

- the old turn keeps its prose ("Classic köttbullar for 4…") above an empty slot;
- the new card looks like any other card, so "did it change or is this a second card?" is unclear;
- an update-only reply shows its prose above an empty slot, and once the card is gone from the transcript (Compact, Start New Chat, past the 500 history rows) it shows "Couldn't display this card" with a raw `SURFACE_NOT_FOUND`.

Apple's pattern is Messages' edited message: the bubble shows its latest text with a small "Edited" label under it, and nothing in the conversation shows a stale copy. Crew follows it: one live card, a quiet label on its newest version, and one-line pointers instead of blank slots.

## Rules

- **Unit:** one surface id inside one block. `SurfaceStore` classifies each block once when it is ingested (`Block.surfaces(created:revised:updated:)`, `.lost`, `.failed`), and `SurfaceBlock` draws from that plus `owners` (which block holds each card) and `present` (cards created by blocks in the current transcript).
- **Re-created card (same id, later `createSurface`):** the newest block owns the card (unchanged). Under that card, a caption "Updated" in `.footnote`, secondary, leading, like Messages' "Edited". A card created once has no caption.
- **Old turn of a re-created card:** where the card was, one line: `<title> · updated below` with an `arrow.down` symbol, `.footnote`, secondary. The title is the live card's title (the same title the pinned chip uses: Header title, else the first Text line, else "Card"). Several refinements: every older turn shows the line; only the newest block shows the card. After "make it vegan" the line shows the new title, since it points at the card as it is now.
- **Update-only block for a card in this transcript:** one line `Updated <title>` with an `arrow.up` symbol in the same style, where the card would be. The card itself changes in place (unchanged behaviour), wherever it is.
- **Update-only block for a card not in this transcript** (the processor never had it, or it is not in `present`, e.g. after Start New Chat or Compact, where the `ChatView` and its processor stay alive): one line "Updated a card that's no longer in this chat" in the same style, never the "Couldn't display this card" chip. A block that is neither (invalid JSON, schema error, unknown component, over 64 KB) keeps the chip.
- **Mixed block** (creates one card and updates another): the created card draws as usual and the update gets its own line under it. Updates to a surface created in the same block draw no line.
- **Not tappable yet.** Showing the earlier version read-only is #227's follow-up (step 3 of the comment); opening the full card from these lines comes with the compact card previews (queued next), which present every card from one sheet.
- **Never a heuristic:** Crew only follows ids; two cards with the same Header title and different ids are two cards.

## Surfaces and directions

- **Bot Chat, iPhone and Mac, light and dark:** iOS `MarkdownText` and Mac `ReplyText` both draw `SurfaceBlock`, so the lines and the caption come from `SurfaceBlock` once. Secondary label colour and `.footnote` adapt to light and dark and Dynamic Type; symbols are decorative, the text carries the meaning for VoiceOver.
- **Rooms:** same transcript view, same rules, any member's card.
- **Other Conversations sheet:** same rules inside its own transcript.
- **Pinned bar and its sheet:** no caption there (the bar stays one line). A re-created card is a new block with a later time, so it auto-pins and the bar title follows (pinned-card spec, `ChatPinsTests`); an update-only block is not a new card, so the pin is unchanged and the bar and an open sheet show the live surface.
- **Streaming:** while a turn streams its card still shows "Preparing card…" (progressive rendering is the next PR). When it finishes, the older turn's card turns into the pointer line in the same sync.
- **Bot list preview, time, status, unread, push, inspector:** unchanged; the bot's prose carries the reply.
- **Other apps (Hermex, Desktop), and Rich UI off:** blocks stay code; nothing changes.
- **Compact previews (next PR):** the caption goes under the preview tile and the pointer lines keep their own text; the preview's summary does not replace them.
- **Sender, receiver, replies back:** the bot chooses the id; the user's button taps on the live card still send the hidden action row and the reply follows these rules.

## States

- **Offline or history reload:** the same rows give the same lines; nothing is stored.
- **Long title:** the line wraps like the prose around it (no truncation; it is one short line in practice).
- **No title:** "Card · Updated below" and "Updated card".
- **Identical repeated block** (word for word): out of scope; both turns draw the same live card, as today.
- **Re-create that fails** (the new block is invalid): the new turn shows the failure chip and the old turn shows what the processor kept (often nothing, since the old surface was deleted first). Known limitation, as today.
- **Out-of-order pages** (room pages and older history pages arrive newest first): ingest follows arrival order, so a late older create can take the card back and an update that arrives before its create is classified as "no longer in this chat" until the chat is reopened. Known limitation of `SurfaceStore`'s arrival-order ingest, unchanged here.
- **Rooms with two bots using the same id:** they replace each other's card and get pointer lines; ids are named after the thing, so this is rare. Accepted.
- **Scroll position:** a re-created card arrives at the bottom where the user just typed; the older card shrinking to one line above happens off screen in the usual case. A user scrolled up into the old card sees it collapse. Accepted (the transcript keeps its existing anchoring).
- **Ticked checkboxes:** a re-created card starts from the data the bot sent (client state is not sent to the bot); unchanged.

## Tests

`CrewTests` replays `Tests/fixtures/chat.a2ui-update.history.json` (recorded on a throwaway clone of `crew-test` with skill v7: köttbullar for 4, "make it for 6" re-sending `kottbullar-for-four`, a tick-off as an update-only `updateDataModel`, and a vegan version as a new id) through `Transcript(history:)` and `SurfaceStore.sync`, and asserts per assistant block what `SurfaceBlock` draws: the old turn's pointer line, the new card with the caption, the update line, the vegan card without a caption, the newest card handed to the pins; and with the first two turns dropped, the update's "no longer in this chat" line instead of a failure. Each assertion fails on `main` (empty slot, no caption, failure chip).
