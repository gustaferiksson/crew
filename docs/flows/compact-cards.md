# Compact cards: the transcript shows a preview, the card opens in a sheet

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
- **Streaming:** "Preparing card…" until the reply finishes, as before. (If progressive cards, #240, lands first, its streaming preview becomes this compact preview in a follow-up, titled from the partial surface.)
- **Without a chat** (a transcript with no `ChatView` container to present from): the card draws in full inline, as before.

## The card sheet

- **One presentation per chat**, owned by `ChatView` (the screen container, per PLAN's presentation rule): `openedCard` is set by the pinned bar and by any transcript preview. `.sheet` on every platform:
  - iPhone: medium and large detents, background interaction up to medium, as the pinned-card sheet today.
  - iPad and Mac: a sheet sized 440 × up to 560 pt like today's popover content. The Mac pinned bar's popover becomes this sheet, so the bar and the transcript open the same thing everywhere.
- **Toolbar:** close (`Button(role: .close)`, Escape on Mac) and Pin/Unpin for that card when the chat can pin (Bot Chat and rooms). Unpin keeps the sheet open now that the sheet is not tied to the bar; Pin likewise.
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

## Tests

- `CardSummary` reads title, subtitle, symbol and image from the recorded köttbullar card (`Tests/fixtures/chat.a2ui-update.history.json`) and falls back for a Header-less v0.21.7 recipe card; the subtitle assertion fails on `main`.
- Renders: `chat-a2ui` and `chat-a2ui-updates` (previews), `chat-a2ui-pinned` with the sheet open, iPhone and Mac, light and dark.
- UI tests that drove inline cards (`CarouselUITests`, `CarouselMacUITests`, `PinnedCardUITests`) open the card first; the iOS ones run locally on a private simulator.
