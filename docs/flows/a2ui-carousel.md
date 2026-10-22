# A2UI Carousel: a swipeable row of items (#125)

A bot recommending several comparable things (products, places, hotels, recipes) today stacks them in one tall card with a hero image and paragraphs per item (Vera's slippers, 2026-10-22), which is hard to scan and scrolls a lot. New: a `crew/v1` `Carousel` component that shows one item at a time, swipeable sideways with the next item peeking, like the App Store's Today rows and the Apple Store app's product shelves. Also fixes the raw `### ` heading seen in that card's Text.

## Payload (`crew/v1`, plain values like Header, KeyValue and Map)

`{"id": "picks", "component": "Carousel", "items": [{...}, ...]}`, each item:

| Key | Required | Shown as |
| --- | --- | --- |
| `title` | yes | headline, up to 2 lines |
| `subtitle` | no | meta line under the title (shop, area, rating), footnote secondary, 1 line |
| `image` | no | https photo at the top of the item; other schemes are ignored |
| `price` | no | trailing the meta line in semibold, never truncated (e.g. "235 kr") |
| `badge` | no | a Badge capsule above the title ("Cheapest", "Best fit"), `tone` as Badge |
| `text` | no | one short sentence, up to 3 lines; bold and italic kept, links dropped (links go in `url`) |
| `url` | no | https link; the whole tile opens it and shows an "Open" label |

Items are data, not child component ids, so every item has the same layout and the model can't build mismatched pages. Per-item buttons that send an action back to the bot are out of scope (a choice goes in a Button or ChoicePicker under the carousel, as today). A carousel with 0 items renders nothing; a missing `title` fails schema validation like any other invalid component ("Couldn't display this card").

## The component

- **Placement:** inside the card's Column like a Chart or Map. As a child of the root card (the skill's only placement) the scroller extends to the card's glass edges (a negative 20 pt horizontal padding cancelling the surface's padding) and gets the 20 pt back with `.contentMargins(.horizontal, 20, for: .scrollContent)`, which is what `.viewAligned` snaps against, so a settled tile lines up with the Header and the next one peeks to the glass edge, the App Store pattern. Inside a nested Card (an inset group) it does not bleed: the nested Card sets the bleed to 0 through the environment and the carousel stays inside its parent with no margins.
- **Item:** an inset tile like a nested Card (`.fill.quaternary`, 16 pt corners), padding 12. With a `url` the whole tile is one button (plain style, dims while pressed). Top: the image area, a fixed 160 pt high, full-width area with 12 pt corners (4:3 is too tall in a chat); the photo is scaled to fit (product shots are often tall and must not be cropped) on a `.fill.tertiary` backdrop. Then badge, title, meta line with price trailing, text, and at the bottom an "Open" label with `arrow.up.right` in the tint colour (a label, not a separate button; the tile is the target). Tiles in one carousel are the same height (the tallest), with the Open label pinned to the bottom so they line up. Long-press (iOS) or right-click (Mac) shows Open, Copy Link and Share, like a link preview in Messages.
- **Width:** with 2+ items each tile is the column width minus 16 pt, so with the 12 pt gap 24 pt of the next tile is visible past the column edge (inside the glass margin); with 1 item the tile is the full column width, nothing peeks, nothing pages. Without bleed (nested Card) the tile is the parent width minus 36 pt, the same 24 pt peek. The card's 560 pt max width caps it on Mac; at the 320 pt Mac column minimum and on the smallest iPhone the tile stays at least ~230 pt wide.
- **Paging:** a horizontal `ScrollView` with `scrollTargetLayout` and `.viewAligned` snapping, so a swipe settles on an item edge; a fast flick may move more than one, like the App Store. Bounces only when content is wider than the view (`scrollBounceBehavior(.basedOnSize)`). The last tile settles against the trailing margin.
- **Current item:** computed from the scroll offset (offset over tile width plus gap, rounded), and the last item once the scroller is at its end, so when the last tile is fully visible the last dot is current and the Mac right arrow is hidden.
- **Page indicator:** with 2 to 10 items, a row of dots centred under the tiles (7 pt, current `.primary`, others `.tertiary`, like `UIPageControl`). The whole row (28 pt high, full width) is the hit area: a tap or click left of the current dot moves one item back, right of it one forward, as `UIPageControl` does. Over 10 items there is no indicator (the skill caps at 10). Hidden from VoiceOver (the tiles say "1 of 4").
- **Mac:** trackpad two-finger horizontal swipe scrolls it (the ScrollView's own behaviour); a mouse wheel's vertical scroll passes to the transcript. On hover, round glass chevron buttons (`chevron.left` / `chevron.right`, 32 pt) appear over the left and right edges of the tile row, vertically centred on the image area; the left one is hidden on the first item and the right one on the last. Clicking moves one item. Arrows fade in and out with the hover (under Reduce Motion they just appear). They are pointer-only; keyboard users Tab through the tiles (each is a button) and the carousel scrolls to the focused tile. iPhone has no arrows (touch has the swipe and the peek).
- **Vertical scroll:** the transcript is a vertical `ScrollView`; the carousel is a nested horizontal one, the same arrangement Table already ships. UIKit/AppKit lock a drag to its dominant axis, so a vertical drag that starts on the carousel scrolls the transcript and a horizontal one pages the carousel. Verified by a UI test (below).
- **Reduce Motion:** dot taps and Mac arrows jump without the scroll animation.
- **Busy turn:** like every surface (Map's Open in Maps included), the surface is disabled while the chat's last turn runs, so tiles don't open and the carousel may not scroll until the turn finishes. Accepted and consistent with today; a separate change can exempt link-only controls from the busy state.

## Text headings (bug)

`CrewText` parses inline markdown only (`inlineOnlyPreservingWhitespace`), so a line starting `### ` shows the hashes. Every line that starts with 1 to 6 `#` and a space now drops the marker and renders bold (the heading's emphasis without changing the Text's size; real section titles use `variant: h4`). Bold is added as an attribute (`stronglyEmphasized` merged into each run's inline intent) on that line's parsed text, so links, italics and existing bold in the line survive. Text without a heading line parses exactly as before, so single line breaks keep working (switching to full markdown would merge them in every existing card). The same treatment applies to Steps items and carousel item text. `#hashtag` without a space and `#` mid-line are left alone. The skill also tells the model not to put `#` headings in `text`.

## Skill (`crew-ui`, version 6)

- Carousel under Crew-only components with every key above.
- When: 2 or more comparable items the user will pick between (products, places, hotels, listings), each with a short title and ideally a photo and link. Not for steps, facts or a single item (use Header/KeyValue).
- Keep per-item text to one short sentence (it shows up to 3 lines), price in `price`, shop or area in `subtitle`, the link in `url` (no links in `text`), the reasoning and caveats in the prose before the block. Up to 10 items.
- No Header `image` when the Carousel has images (the card would stay tall); put the carousel directly in the root Column.
- No markdown headings in Text; use `variant`.
- An example with 3 items, appended after the existing examples (the fixture code indexes the first three).
- Frontmatter description stays under 60 characters.

## Surfaces and directions

- **Chat, iPhone and Mac, light and dark:** the only surface; the carousel lives inside a reply's A2UI card. Same view on both platforms except the Mac hover arrows.
- **Bot to user only:** the bot sends the block; a tile opens its link through the transcript's `openURL` (in-app Safari sheet on iPhone, the browser on Mac, as links in Text do). Nothing is sent back to the bot; no hidden `<a2ui-action>` row.
- **Other chats (rooms, Bot Chat, conversation sheet from search):** same `SurfaceBlock`, same rendering.
- **Bot list preview, push, inspector:** unchanged. The preview and push show the reply's prose (the block is code); the skill's "prose first" rule carries the answer there and in other apps (Hermes Desktop, Hermex show the block as code).
- **Older Crew builds:** an unknown component fails the whole card as "Couldn't display this card" with the raw block in a disclosure; the prose still carries the answer. The skill lives on the server profile, so once a new build on one device installs version 6, an older build on another device (say a Mac not yet updated) shows that chip for every carousel. Accepted degradation until it updates.
- **History reload:** the block is transcript text, so it renders the same after a reload; the scroll position resets to the first item.

## States

- **1 item:** full-width tile, no dots, no arrows, no paging.
- **Many items:** dots up to 10, none above; lazy layout is not needed at this size (the skill caps it at 10).
- **Missing image:** if no item has an image, there is no image area at all. If some do, items without one show the backdrop with a `photo` symbol so tiles stay equal height.
- **Image loading / failed / offline:** the backdrop with a small progress view while loading; on failure or offline, the `photo` symbol. The card itself never fails over an image.
- **Long title:** 2 lines, tail truncation. **Long subtitle:** 1 line, truncated, price never truncated. **Long text:** 3 lines, tail truncation. VoiceOver reads the full strings.
- **Missing url:** no Open label, no context menu; the tile is not a button. Non-https url: treated as missing.
- **Large Dynamic Type:** tiles grow taller (equal height, the tallest wins); widths stay; dots stay one row. At accessibility sizes the title may use 4 lines and the meta line stacks (subtitle above price).
- **Streaming:** "Preparing card…" until the reply finishes, as today.

## VoiceOver and keyboard

- Each tile is one element: "Best fit, Evi Beige, Jakobs Handmade, 235 kr, <text>, 1 of 4", with the link trait when it has a url (double-tap opens). Swiping right moves through tiles and the carousel scrolls to follow focus.
- The dots are hidden from VoiceOver. Mac arrows are labelled "Previous" and "Next".
- Mac keyboard: Tab (with keyboard navigation on) reaches each tile; the carousel scrolls to the focused one.

## Tests

- Unit (`CrewTests`): the heading transform on the real line from Vera's card (`### 1. [Evi Beige, Jakobs Handmade](…) · 235 kr` becomes bold text with the link kept and no `#`), a heading line that already contains `**bold**`, `#hashtag`, mid-line `#`, and multi-line text keeping its line breaks.
- UI (`CrewUITests`, `-snapshot chat-a2ui-carousel`, replaying a real `crew-test` reply): every item tile from the fixture is reached by swiping left (its label "…, k of n" becomes hittable), swiping to the end shows the last tile ("n of n"), no static text starts with `#`, and a vertical swipe starting on the carousel scrolls the transcript (the Header moves) while the same tile stays current.
- Shown failing first: the UI test on main shows "Couldn't display this card" (unknown component) and the unit test shows the `###`.
- Mac UI (`CrewMacUITests/CarouselMacUITests`, CI only): hovering shows Next and no Previous on the first item, Next brings item 2 to the leading edge, and the run attaches the Mac light, hover and dark screenshots.
- Renders: `chat-a2ui-carousel` (the real reply) and `chat-a2ui-carousel-states` (a `###` Text line, a failed photo, a missing photo, a long title, subtitle and text, a single item without a link), iPhone light and dark, committed to `docs/flows/renders/`; Mac from the CI attachments. Judge the dark render for white product photos on the dark backdrop.
- Real server: the fixture is a real reply from the `crew-test` profile with the version 6 skill installed (`Tests/chat_probe/run.sh a2ui` with `A2UI_PROMPT`).
