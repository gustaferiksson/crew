# Compact cards: the transcript shows a preview, the card opens in a sheet or popover

User decision (2026-11-01): A2UI cards in the transcript render like iMessage app messages, a compact preview that opens the full interactive card. Until now each card drew in full inline (a recipe is 600 pt or more), the newest one also opened from the pinned bar, and the same card could sit in two places with its controls (ticks, sliders, form fields) visible in both. Now the full card lives in one place, the card sheet, and the transcript and the bar are two ways to open it.

Apple's pattern: Messages draws an app message (Apple Pay, Fitness, a game, a poll) as a compact bubble with an icon, title and caption, and tapping it opens the full experience in a sheet. Crew follows it.

## The preview

- **Content**, from the live surface (`CardSummary`, also used by the pinned chip):
  - the 44 pt tinted symbol tile from the Header (`symbol`, `tone`; `rectangle.on.rectangle` and the accent colour when missing);
  - the title (Header `title`, else the first line of the first Text, else "Card from <bot>" / "Card"), `.headline`, up to 2 lines;
  - one summary line: the Header `subtitle`, `.subheadline`, secondary, 1 line; none when the card has no subtitle;
  - an optional trailing 44 pt thumbnail: the Header `image` (https, through `CachedImage`), rounded like the tile.
- **Shape:** the same glass card as before (`.regular` glass behind the content, 28 pt corners, 560 pt max width, leading), 12 pt padding, so it reads as the card in its closed state and keeps the transcript's rhythm. Light and dark come from the glass and semantic colours.
- **Tap:** opens the card sheet for that surface id. The whole preview is one button (`.plain` style): VoiceOver reads the title, the summary as its value, and "Shows the card" as its hint.
- **Context menu:** Expand Card / Collapse Card, then Pin Card / Unpin Card.
- **While a turn runs:** the preview stays tappable; the card inside the sheet is disabled while a turn runs, as before.
- **Card updates (`docs/flows/card-updates.md`):** unchanged rules. The "Updated" caption sits under the newest preview; older turns keep their one-line "updated below" pointer; update-only replies keep "Updated <title>". The preview reflects the live surface, so an update-only change of title or subtitle shows in it.
- **Streaming (progressive cards, #240):** the half-written card shows as this compact preview, titled from the partial surface (`CardSummary` of the preview model), dimmed and not tappable until the reply finishes, when the finished card's preview takes its place.
- **Small choice cards** (two or three buttons): also a preview, per the user's decision; answering takes one more tap. The tapped button's mark shows inside the sheet.
- **Search:** a hit inside a card's text highlights the turn; the card itself stays closed.
- **Thumbnail:** the Header hero image is cropped to fill the 44 pt square (`scaledToFill`), like Messages' link thumbnails.
- **Haptics and keys:** none on open (like the pinned chip). On Mac the preview is a button: Tab focuses it and Space opens it; Escape closes the sheet.

## Expanding a card in place

User request (2026-11-01, after compact cards shipped): a preview can also expand into the full, interactive card right in the transcript and collapse back. Opening the sheet and the pinned card stay exactly as they are.

Apple's precedent is Reminders: a reminder with subtasks has a disclosure chevron of its own that shows them in place, while tapping the row itself opens the reminder for editing. Crew does the same: the row's tap keeps opening the sheet, a chevron beside it expands the card in place. The chevron is the HIG disclosure button (`chevron.down`, flipping to point up while expanded), not a trailing `chevron.right`, which on iOS reads as the row's drill-in indicator.

- **Affordance:** a trailing disclosure button in the preview row, after the thumbnail: `chevron.down`, `.footnote.weight(.semibold)`, secondary, rotating 180 degrees while expanded, with a 44 pt square hit area on iOS and 28 pt on the Mac (both `@ScaledMetric`), outside the row's open button. Tapping it toggles with `.smooth`; tapping anywhere else on the row still opens the sheet. The row's context menu gains Expand Card / Collapse Card (`chevron.down` / `chevron.up`) above Pin Card / Unpin Card. The context menu stays on the row only, so a long press lifts the row, not a screen-tall card, and long presses inside the expanded card's controls are theirs.
- **Expanded:** the same glass card grows: the preview row on top, unchanged, then the live surface below it (20 pt sides and bottom as in the sheet and the pre-compact inline card, 8 pt from the row). The row already is the header (symbol, title, subtitle, thumbnail), so the inline surface hides exactly the Header node `CardSummary` picked, matched by its component id through an environment value (`hiddenHeader`); any other Header (nested, in a template) still draws. A hero image therefore shows only as the row's thumbnail inline; the sheet still shows the whole Header. A card without a Header takes its title from its first Text, which then also shows inline under the row (accepted). The popover anchor stays the row's frame, not the expanded card's.
- **The card inline is the real card:** its buttons send the same hidden action as the sheet, it is disabled while a turn runs (the chevron and Collapse stay enabled), and the tapped button's mark shows. Offline it behaves as the sheet does.
- **Same data, separate view state:** inline and sheet render the same `SurfaceViewModel` (`surfaces.processor.surfaceGroupModel[id]`), the same choice mark (`surfaces.choices[id]`) and the same owner id, so values never diverge: a field's text, a slider's value, a checklist tick or a choice made in one shows in the other. View state is per presentation, as in any two views of one document: a carousel's page, a map snapshot, text-field focus.
- **Expanded state:** a `Set` of surface ids owned by `ChatView` (the screen container) and handed to rows through the environment like `openedCard`, so a lazy row recycled while scrolled away comes back expanded. Keyed by surface id: a follow-up that re-creates the same id ("make it vegan") keeps the card expanded at its new place, and the older turn keeps its "updated below" line. Ids of cards that left the transcript stay in the set harmlessly until the chat closes. Not persisted: it lasts while the chat is on screen (switching chats, a new window or a relaunch starts collapsed); persisting would mean a new field and a migration in `pins.json` or another file, not worth it for a view toggle.
- **Scroll position:** expanding grows the row downward and the row stays where it is, also for the newest card at the end of the transcript: the content grows taller, which is not a case `TranscriptScroll`'s end hold acts on (it re-pins only when the content did not grow), and Jump to Latest appears so the user can follow it down. Collapsing from the chevron keeps the row in place (the chevron is in the row, so the row is on screen). There is no collapse from inside a long expanded card; the user scrolls up to the row, as in Reminders.
- **Streaming preview, failed and lost cards:** no chevron (the streaming preview is not a finished card; a failed card has its own "Couldn't display" disclosure; an update line has no card).
- **Pinned card, the sheet and requests:** unchanged. Opening the sheet does not collapse the inline card and vice versa; a request card closing the sheet leaves the inline card expanded.
- **Search:** a search jump into a turn with an expanded card highlights the turn as before; the card's state is unchanged.
- **Surfaces:** Bot Chat and rooms on iPhone, iPad and Mac, light and dark; the Other Conversations sheet's `ChatView` owns its own set; each Mac chat window has its own (a toggle in one window does not expand the card in another, like the open sheet).
- **VoiceOver and keys:** the disclosure button is labelled "Expand" or "Collapse" with the card title as its value; the row's button also carries an "Expand Card" / "Collapse Card" accessibility action. Mac: the button is focusable by Tab with full keyboard navigation and Space toggles it.
- **Width and Dynamic Type:** the button keeps its hit area; the expanded card is the 560 pt max-width glass card, as cards were inline before compact cards.

## The card sheet

- **One open card per chat**, owned by `ChatView` (the screen container, per PLAN's presentation rule): `openedCard` (id plus anchor frame) is set by any transcript preview (with its frame) and by the pinned chip above the composer (no anchor: the popover follows the chip's current frame, `docs/flows/pinned-card.md`). One `.popover` with `.presentationCompactAdaptation(.sheet)`, so at most one card is open. While a card is open, a tap on another preview or on the chip changes only the card id and keeps the current anchor:
  - iPhone: medium and large detents, background interaction up to medium, as the pinned-card sheet today.
  - iPad and Mac: a popover anchored on the tapped preview (440 pt wide, at most 560 pt tall, the card scrolling inside), the pinned card's popover (user, 2026-11-01: the pinned behaviour is "perfect", and a modal sheet would block asking follow-ups). Clicking into the composer or elsewhere closes it; Escape closes it.
  - The popover is presented by `ChatView` (the container) with `attachmentAnchor: .rect(...)` at the frame the preview reports in the chat's coordinate space, so no row presents anything and a recycled row cannot dismiss it.
- **Toolbar (iPhone sheet):** close (`Button(role: .close)`) and Pin/Unpin; on iPad and Mac the popover has the Pin/Unpin button in a small row at its top and no close button (popovers close by clicking outside or Escape), for that card when the chat can pin (Bot Chat and rooms). Unpin keeps the sheet open; Pin likewise.
- **Opening:** dismisses the keyboard first, like the pinned chip. Tapping another preview while the iPhone sheet sits at medium swaps the sheet to that card.
- **A request card arrives** (approval, question): the sheet closes so the request gets the attention, as pinned-card.md does for the popover today.
- **Content:** the live surface, scrolling, with the card's title as navigation title (iPhone, iPad) and the existing button-choice marks; disabled while a turn runs. Taps send the hidden action row as before and the reply streams behind the sheet.
- **The card changes while open:** follows the surface id (re-created or updated); closes when no surface with that id is left in the transcript, as today.

## Surfaces and directions

- **Bot Chat and rooms, iPhone, iPad and Mac, light and dark:** as above.
- **Other Conversations sheet:** previews open the card sheet over that sheet (its `ChatView` presents it); no Pin button there (no pin key).
- **Mac chat windows:** each window's `ChatView` presents its own sheet.
- **Pinned card:** the chip above the composer (`docs/flows/pinned-card.md`) opens the same sheet.
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

- `PinnedCardUITests` (iOS): the pinned chip and the transcript preview open the same sheet, which stays open 3 s; Pin in the sheet pins and keeps it open. A real-server probe is not needed: no server traffic changes.
- `CardSummary` reads title, subtitle, symbol and image from the recorded köttbullar card (`Tests/fixtures/chat.a2ui-update.history.json`) and falls back for a Header-less v0.21.7 recipe card; the subtitle assertion fails on `main`.
- Renders: `chat-a2ui` and `chat-a2ui-updates` (previews), `chat-a2ui-pinned` and `chat-a2ui-streaming`, iPhone and Mac (the Mac popover is a separate window the offscreen renderer does not capture; `CarouselMacUITests` attaches screenshots of it in CI), light and dark.
- `CardExpandUITests` (iOS, fixture `chat-a2ui-pinned`, which opens at the end of the transcript): the newest card starts collapsed; its disclosure button expands it in place (a carousel item of the card is in the transcript, no sheet opens) and the row stays on screen; the row's tap still opens the sheet; closing the sheet leaves the inline card expanded; Collapse Card from the row's context menu folds it back and the preview is still hittable. Fails on `main` at the first step (no disclosure button, so the card cannot be shown in place).
- Renders: `chat-a2ui-expanded` (the newest card expanded, its Header hidden under the row) on iPhone and Mac, light and dark.
- `PinnedCardUITests` and `CarouselUITests` run locally to show the sheet is unchanged.
- UI tests that drove inline cards (`CarouselUITests`, `CarouselMacUITests`, `PinnedCardUITests`) open the card first; the iOS ones run locally on a private simulator.
