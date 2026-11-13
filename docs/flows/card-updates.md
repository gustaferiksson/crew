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
- **"Updated below" is tappable (2026-11-13, plan item 3):** the old turn's line is a plain button (same look, the whole line is the hit area, like Messages' tappable "Edited"; on iOS the line is at least 44 pt tall for the HIG minimum hit target, on the Mac it keeps its text height). A tap scrolls the transcript to the turn that now owns the card, centred, and tints that turn for 2 seconds, the same mechanism a search hit uses (`ChatView`'s `position.scrollTo(id:anchor: .center)` and `highlighted`). The turn comes from `SurfaceStore.cardTurns` (surface id to the id of the turn holding its owner block, filled during `sync`), so a tap never guesses. The card's expanded or collapsed state is unchanged; on iOS the sheet is not opened (the preview row is right there). VoiceOver reads the line as a button with the hint "Shows the current version". Known gap: VoiceOver focus stays on the line after the jump (the search jump has the same gap); moving it to the target turn belongs to the accessibility pass (#232). The "Updated <title>" line (update-only reply) and the "no longer in this chat" line stay plain text: the first points up at a card the reader just passed, the second has nothing to show. Showing the earlier version read-only is not built (the bot's prose above the line describes it).
- **Never a heuristic:** Crew only follows ids; two cards with the same Header title and different ids are two cards.

## Animated changes (2026-11-13, plan item 3)

Apple's pattern: Reminders and Wallet change a value in place with a short animation (a number rolls, a check mark draws, a row fades in), never a pop. Crew does the same with standard SwiftUI only.

- **One transaction for the whole change:** `ChatView` runs `SurfaceStore.sync` (where every bot block is ingested, so `updateDataModel`, `updateComponents` and a same-id re-create all land) inside `withTransaction(.cardUpdate(from:to:reducingMotion:))`, given the turn statuses before and after. The A2UI `SurfaceViewModel` rebuilds its tree synchronously, so every card view reading the surface updates in that transaction.
- **Only live changes animate (reviewer):** the transaction animates only when a turn that was streaming has finished (statuses compared from the end, so a prepended page does not shift them); a turn that arrives already finished (a room member's turn delivered whole) changes in one step. Opening the chat (the initial sync, which also restores saved card state), history arriving into an empty chat and Load Earlier (turns prepended, older blocks replayed) draw the final state in one step.
- **What moves:** numbers and short values roll with `.contentTransition(.numericText())` on the values that are usually numeric: a KeyValue value, a Table cell, a Badge and the preview's subtitle. A check box a bot ticks animates its existing `symbolEffect(.replace)` mark and strike-through, as a user tap does. Rows a bot appends or removes at the end (List children, Table and KeyValue rows) fade in and out (the default opacity transition); those rows are keyed by index, so a row removed in the middle shows as the rows below it changing their text and the last row fading out (accepted: bots rarely remove a middle row, and the data has no stable row id). A re-created card (same id, new block) is a new view at its new turn, and its old turn's card turns into the "updated below" line with the same fade; values inside a re-created card do not roll (its `Surface` is reset by `.id(owner)` so carousel pages and field focus start fresh).
- **Animation:** `.smooth` (Apple's default spring), the same as card disclosures.
- **Reduce Motion:** no animation at all; the transaction carries no animation, so content transitions and fades do not run either (the change is one step, as the disclosures' Reduce Motion behaviour in the work log).
- **At the end of the transcript:** the transaction is a disclosure transaction (`Transaction.disclosure`), so `TranscriptScroll` drops its animation while it follows the end and the reader is within 40 pt of it (PLAN, "Disclosures at the end"): a card that grows or shrinks there would otherwise fight the end holds (iOS 27 leaving content under the composer, the Mac re-running its end hold every frame). So an expanded card at the end (the usual Mac case) changes in one step; scrolled up, it animates. The search jump and Jump to Latest are their own transactions and are unaffected.
- **Outside the transcript:** the iPhone card sheet, the iPad popover, the pinned-card sheet (iPhone and Mac) and the pinned chip above the composer (its subtitle already rolls with `.numericText()`) sit outside `TranscriptScroll`, so a bot update animates there even at the end (the common iPhone case: the card is open while the reply arrives).
- **The user's own taps** keep their existing animations (`withAnimation(.snappy)` on a check box).

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

- **Offline or history reload:** the same rows give the same lines; nothing is stored. Opening a chat draws cards in their final state; nothing animates on the first sync (no earlier state to animate from).
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

Item 3 adds: the same fixture asserts `cardTurns` maps the recipe to the "make it for 6" turn and the vegan card to its own turn (the tap target), and `Transaction.cardUpdate(from:to:reducingMotion:)` carries `.smooth` for a reply that finished, and no animation under Reduce Motion, on the initial sync, for history arriving into an empty chat or for Load Earlier; both shown failing before the change. Renders of the before and after frames of the tick-off update (Mac expanded card, iPhone sheet) are checked; the animation itself is not visible in a still and is verified only by the transaction test.
