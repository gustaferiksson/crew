# Progressive cards: a card draws while the bot writes it

A recipe card took about 29 s from send to visible, 22 s of it "Preparing card…" while the model streamed 1,300 tokens of A2UI JSON (#227 research). Crew only rendered a card after the turn finished. Text in the same reply already streams in; the card should too, the way Messages and Safari draw a page as it arrives instead of a spinner until the last byte.

## Rule

- While the turn streams, the open ```` ```a2ui ```` fence is healed and drawn: keep every complete message and every complete object inside an array (a component, an ingredient, a carousel item), drop the half-written tail, close the open brackets (a minimal port of the A2UI Python SDK's partial-JSON reader, `PartialA2UI.swift`). The result goes to a scratch `MessageProcessor` (never the chat's live one), so half a card never replaces or moves a live card and never reaches `owners`, `present`, the pins or the bar.
- The card appears once its root, Column and Header are complete: with skill v7's component-first order, after 602 of 3,662 bytes of the recorded köttbullar block (17%), instead of at the end. Sections fill in as their components complete; ingredient rows appear when the data model arrives last.
- The preview is disabled (no taps, no checkbox state) and dimmed like any card while a turn runs, in the same glass card, so the finished card replaces it in place with the same look. When the turn finishes, the existing sync ingests the full block and the normal card (with its update caption or pointer lines) takes over.
- Before the Header is complete, and for a block the healer can't parse yet, "Preparing card…" shows as today. If a later prefix fails to process (schema error in a half card), the last good preview stays.

## Cost

- Per token, `SurfaceBlock` only computes `previewStep(forLength:)` (a `log2` of the block length, the `.task(id:)` key); nothing new is parsed per token, so #217/#218's per-token budget holds.
- The step grows with the block (about 30 bytes at the start, 135 bytes at 3.6 KB, 900 bytes at 30 KB), so a refresh costs O(n) but the whole stream stays O(n). On each step the healer scans the block once and, only if the healed text changed, a fresh processor builds the preview. Debug test build (`ProgressiveCardTests`): the recorded 3.6 KB card, 53 refreshes in 138 ms, 0.14 ms per token; a 28 KB card, 117 refreshes in 2.4 s, 0.32 ms per token.
- Previews are cached per surface id with their healed text, so a row the lazy transcript recycles gets its card back without rebuilding, and two cards in one reply each keep theirs. The cache is dropped when the turn ends. Blocks over 64 KB never preview (they become the size chip at the end).

## Surfaces and directions

- **Bot Chat and rooms, iPhone (`MarkdownText`) and Mac (`ReplyText`), light and dark:** both route the open fence to `SurfaceBlock`; same glass card.
- **Pinned bar, bot list preview, push, inspector:** unchanged. A streaming card never pins; it pins when the turn finishes (pinned-card spec).
- **Refinement of a live card (same id):** the preview is separate, so the live card stays where it is until the reply finishes, then moves down with the "updated below" line (card-updates spec). For a moment both are visible; accepted, it is the same moment Messages shows a reply arriving under the message it edits.
- **Update-only blocks:** no `createSurface`, so no preview; "Preparing card…" until the turn finishes, then the update line.
- **Stopped or failed turn:** the partial card stays as the preview until the turn's status changes; then the block is ingested whole and, being invalid JSON, shows the failure chip as today (unchanged; a softer stopped state is a follow-up).
- **Long cards:** the card grows downward like text; the transcript's existing follow-bottom behaviour applies; refreshes thin out as the block grows (see Cost).
- **`<a2ui-json>` tags:** they become a fence only once the closing tag arrives, so that form still streams as text and draws at the end, as today.
- **VoiceOver:** the preview is a dimmed card whose elements grow as it streams, like streaming text; nothing extra.
- **Compact card previews (next PR):** the streaming state should show the compact bubble with the title from the preview (`CardSummary(preview.rootNode)`); `preview(_:)` returns the model so it can.
- **Offline mid-stream:** the stream stops; the preview stays until a reload replaces the turn.

## Tests

`ProgressiveCardTests` replays the recorded köttbullar block (`Tests/fixtures/chat.a2ui-update.history.json`, skill v7) byte by byte: every healed prefix is valid JSON; the Header shows within the first quarter of the block (fails with previews off: no card before the fence closes); an unchanged prefix returns the same preview; the recorded card and an 8x longer one stay under 1 ms per token.
