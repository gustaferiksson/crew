# Compact cards: the transcript shows a preview, the card opens in a sheet or popover

User decision (2026-11-01): A2UI cards in the transcript render like iMessage app messages, a compact preview that opens the full interactive card. Until now each card drew in full inline (a recipe is 600 pt or more), the newest one also opened from the pinned bar, and the same card could sit in two places with its controls (ticks, sliders, form fields) visible in both. Now the full card lives in one place, the card sheet, and the transcript and the bar are two ways to open it.

Apple's pattern: Messages draws an app message (Apple Pay, Fitness, a game, a poll) as a compact bubble with an icon, title and caption, and tapping it opens the full experience in a sheet. Crew follows it.

## The preview

- **Content**, from the live surface (`CardSummary`, already used by the pinned bar):
  - the 44 pt tinted symbol tile from the Header (`symbol`, `tone`; `rectangle.on.rectangle` and the accent colour when missing);
  - the title (Header `title`, else the first line of the first Text, else "Card from <bot>" / "Card"), `.headline`, up to 2 lines;
  - one summary line: the Header `subtitle`, `.subheadline`, secondary, 1 line; none when the card has no subtitle;
  - an optional trailing 44 pt thumbnail: the Header `image` (https, through `CachedImage`), rounded like the tile.
- **Shape:** the same glass card as before (`.regular` glass behind the content, 28 pt corners, 560 pt max width, leading), 12 pt padding, so it reads as the card in its closed state and keeps the transcript's rhythm. Light and dark come from the glass and semantic colours.
- **Tap:** opens the card sheet for that surface id. The whole preview is one button (`.plain` style): VoiceOver reads the title, the summary as its value, and "Shows the card" as its hint.
- **Context menu:** Pin Card / Unpin Card, as before.
- **While a turn runs:** the preview stays tappable; the card inside the sheet is disabled while a turn runs, as before.
- **Card updates (`docs/flows/card-updates.md`):** unchanged rules. The "Updated" caption sits under the newest preview; older turns keep their one-line "updated below" pointer; update-only replies keep "Updated <title>". The preview reflects the live surface, so an update-only change of title or subtitle shows in it.
- **Streaming (progressive cards, #240):** the half-written card shows as this compact preview, titled from the partial surface (`CardSummary` of the preview model), dimmed and not tappable until the reply finishes, when the finished card's preview takes its place.
- **Small choice cards** (two or three buttons): also a preview, per the user's decision; answering takes one more tap. The tapped button's mark shows inside the sheet.
- **Search:** a hit inside a card's text highlights the turn; the card itself stays closed.
- **Thumbnail:** the Header hero image is cropped to fill the 44 pt square (`scaledToFill`), like Messages' link thumbnails.
- **Haptics and keys:** none on open (like the bar). On Mac the preview is a button: Tab focuses it and Space opens it; Escape closes the sheet.

## The card sheet

- **One presentation per chat**, owned by `ChatView` (the screen container, per PLAN's presentation rule): `openedCard` (id plus anchor frame) is set by the pinned bar and by any transcript preview. One `.popover` with `.presentationCompactAdaptation(.sheet)`:
  - iPhone: medium and large detents, background interaction up to medium, as the pinned-card sheet today.
  - iPad and Mac: a popover anchored on the tapped preview or the bar (440 pt wide, at most 560 pt tall, the card scrolling inside), the pinned bar's existing popover (user, 2026-11-01: the pinned behaviour is "perfect", and a modal sheet would block asking follow-ups). Clicking into the composer or elsewhere closes it; Escape closes it.
  - The popover is presented by `ChatView` (the container) with `attachmentAnchor: .rect(...)` at the frame the preview or bar reports in the chat's coordinate space, so no row presents anything and a recycled row cannot dismiss it.
- **Toolbar (iPhone sheet):** close (`Button(role: .close)`) and Pin/Unpin; on iPad and Mac the popover has the Pin/Unpin button in a small row at its top and no close button (popovers close by clicking outside or Escape), for that card when the chat can pin (Bot Chat and rooms). Unpin keeps the sheet open now that the sheet is not tied to the bar; Pin likewise.
- **Opening:** dismisses the keyboard first, like the bar. Tapping another preview while the iPhone sheet sits at medium swaps the sheet to that card.
- **A request card arrives** (approval, question): the sheet closes so the request gets the attention, as pinned-card.md does for the popover today.
- **Content:** the live surface, scrolling, with the card's title as navigation title (iPhone, iPad) and the existing button-choice marks; disabled while a turn runs. Taps send the hidden action row as before and the reply streams behind the sheet.
- **The card changes while open:** follows the surface id (re-created or updated); closes when no surface with that id is left in the transcript, as today.

## Surfaces and directions

- **Bot Chat and rooms, iPhone, iPad and Mac, light and dark:** as above.
- **Other Conversations sheet:** previews open the card sheet over that sheet (its `ChatView` presents it); no Pin button there (no pin key).
- **Mac chat windows:** each window's `ChatView` presents its own sheet.
- **Pinned bar:** unchanged look; tapping it opens the same sheet.
- **Bot list preview, time, unread, push, inspector:** unchanged (they never showed cards).
- **Sender, receiver, replies back:** the bot sends the card; the user opens it, taps; the hidden action goes back and the bot's reply follows the card-update rules.

## States

- **No Header:** title from the first Text line, no summary, default tile.
- **Long title:** 2 lines then tail truncation; long subtitle: 1 line, tail truncation.
- **Failed card:** the "Couldn't display this card" chip, as before (no preview).
- **Offline:** the preview opens the sheet; the card's buttons behave as before.
- **Accessibility sizes:** the row grows with Dynamic Type; the tile and thumbnail are `@ScaledMetric`.

## PLAN.md

The "Pinned card" line's popover and the "Generative UI design pass" line's inline card are replaced by a "Compact cards" Decisions line.

## Tests

- `PinnedCardUITests` (iOS): the bar and the transcript preview open the same sheet, which stays open 3 s; Pin in the sheet pins and keeps it open. A real-server probe is not needed: no server traffic changes.
- `CardSummary` reads title, subtitle, symbol and image from the recorded köttbullar card (`Tests/fixtures/chat.a2ui-update.history.json`) and falls back for a Header-less v0.21.7 recipe card; the subtitle assertion fails on `main`.
- Renders: `chat-a2ui` and `chat-a2ui-updates` (previews), `chat-a2ui-pinned` and `chat-a2ui-streaming`, iPhone and Mac (the Mac popover is a separate window the offscreen renderer does not capture; `CarouselMacUITests` attaches screenshots of it in CI), light and dark.
- UI tests that drove inline cards (`CarouselUITests`, `CarouselMacUITests`, `PinnedCardUITests`) open the card first; the iOS ones run locally on a private simulator.
