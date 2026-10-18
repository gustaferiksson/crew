# Cards above the composer never set the window's height (#60)

On the Mac, a payment card in a chat makes the window jump taller and it can't be made shorter again until the card leaves. iOS is unaffected in practice (the screen can't grow), but the same view code overflows there in landscape or at large text.

## Cause

The window's minimum content size is SwiftUI's size at a zero proposal, so the bar above the composer (`safeAreaBar` in `ChatView`) adds its *minimum* height to the window's. `PaymentCard` pins four texts with `.fixedSize(horizontal: false, vertical: true)` (host, punycode warning, card label, FOR line), and the host is joined with zero-width spaces so it may break anywhere. In the zero-width pass every character of `www.zalando.se` becomes its own `.title2` line, so the card's minimum is several hundred points. Measured with `-snapshot <screen> -measure YES` (window content min height, sidebar-less chat window):

| Screen | Min height |
|---|---|
| `chat-history` (no card) | 96 |
| `chat` (approval card) | 226 |
| `chat-question` / `chat-questions` | 278 / 310 |
| `chat-payment-offer` / `chat-payment-notice` | 184 / 149 |
| `chat-payment` | 987 |
| `chat-payment-punycode` | 1824 |

When that minimum is taller than the window, AppKit grows the window and refuses to shrink it below it.

## Wanted (what Apple does)

Like a Mail or Messages banner and Apple's own sheets: the card is as tall as its content when there is room; when the window is short its body scrolls while the decision buttons (Deny, Hold to Pay) stay pinned and visible, and the transcript above gives way first. The window's minimum height with a payment card is about the same as with any other card, so the user can always resize freely.

## The change

- `PaymentCard`: drop the `fixedSize(vertical:)` pins on its four texts (they only force wrapping that the card's vertical stack already gives when it has room). Since #91 the card pins what the user approves: the header, the "Pay <host>" line (wrapping), the TOTAL row and the buttons have a higher `layoutPriority` than the rest and never scroll. Only the CARD and FOR rows sit in `ViewThatFits(in: .vertical) { rows; ScrollView { rows } }` (`.scrollBounceBehavior(.basedOnSize)`, indicator flashes on appear), and the claim line has the lowest priority, so it truncates first. The claim line can shrink to nothing. In a compact height (iPhone landscape) the card puts header, host and claim beside the CARD/FOR/TOTAL box with the buttons full width below, so it fits under the navigation bar. The card's text is capped at accessibility size 3 so the pinned parts fit an iPhone in portrait at the largest text size, and the bar above the composer is never taller than the area below the navigation bar or title bar (`ChatView` measures the transcript's frame plus its bottom inset, which doesn't change with the bar), so the card can't slide under it.
- **No "Pay…" fallback (#91, user decision):** #72 switched the button to "Pay…" with a confirmation dialog while the body was clipped. It is removed: because host and total are always on screen, the button is always Hold to Pay. A tap, Space or Return and VoiceOver still open the "Pay <amount> at <host>?" dialog as in `payments.md`.
- `ShopOfferCard`: keeps its punycode-warning pin. It wraps per word, not per character, so it adds at most a few lines to the minimum (`chat-payment-offer` measures 184 pt), and dropping it would let anti-phishing text truncate. The Add Shop sheet repeats the warning.
- Approval and question cards: no pinned texts, minimums 226 and 310 pt, the same as before this bug; unchanged. Payment notice: unchanged. The composer's own growth (draft up to its line limit, attachment tray) adds to the minimum as it does today, with or without a card.
- `Snapshot.capture()` gains a `-snapshotHeight <pt>` launch argument that sets the window's content height before the capture, for the short-window renders.
- No locked UI value changes (cards stay 560 pt max with 16 pt sides; composer, jump arrow unchanged).

## Surfaces and directions

- **Chat, Mac (main window with sidebar and inspector, and the separate chat window):** the card shows in full at normal heights (pixel-identical renders); at a short window the body scrolls and Deny / Hold to Pay stay visible above the composer; the window resizes freely while the card is up and doesn't grow when it arrives.
- **Chat, iPhone:** looks the same at normal sizes; in a short layout (landscape, keyboard up, large text) the card grows and the transcript gives way; when even that isn't enough, CARD and FOR scroll and the claim line truncates. A payment card arriving, a tap on it or a downward swipe on it dismisses the keyboard (the draft stays). The swipe never dismisses the card: a payment request leaves only through Deny, Pay or expiry (#91).
- **Hold to Pay, Deny, countdown, Try Again, approved state:** unchanged at every height; Hold to Pay never changes into another button.
- **Bot list (preview, time, status, unread), push, inspector:** unchanged; nothing here touches requests or state.
- **Sender / receiver:** unchanged; the card's answers and their server calls are untouched.
- **Groups:** rooms show no payment cards (PLAN.md), unchanged.
- **Light and dark:** glass card unchanged; rendered both.

## States

- Loading, failed lookup, unverified, punycode, countdown, approved, offline (card disabled): same content, same fit rule.
- Long content (long punycode host, long FOR text up to 3 lines): wraps when there's room, scrolls inside the card when there isn't; never grows the window.
- Accessibility text sizes: the card's text stops growing at accessibility size 3; header, host, total and buttons stay fully visible and the middle rows scroll.
- Resized mid-hold: the button and its gesture stay in place, so the hold continues.
- VoiceOver and keyboard: the scroll view keeps every row reachable; the card's summary label (host, merchant, total) is unchanged.

## Related: #10

`layout-inspector` measures min 1240 x 202 with the inspector open: a width problem from the `.inspector` column (SwiftUI bug described in #10), not this height bug. Not fixed here.

## Tests

- Unit (`CardHeightTests`, macOS, unhosted; adds `Sources/Chat/PaymentCard.swift` to the CrewTests sources in `project.yml`): `PaymentCard` built from the recorded `approval-frame.json` request and `request-pending.json` details (host swapped for the punycode case), hosted in `NSHostingController` at the bar's 560 pt max width. For the verified, loading, failed and unverified states and both hosts, its minimum (`sizeThatFits(in: .zero)`, the pass the window's minimum comes from) is at most `ApprovalCard`'s and under 160 pt, and its ideal height is at least 60 pt more; at a 2000 pt proposal it reports exactly its ideal height (no scroll with room) and at 200 pt it fits. Fails on main (minimum 987 pt for `www.zalando.se`).
- UI (`PaymentUITests`, iOS Simulator): iPhone landscape, landscape with a punycode host, and the largest accessibility text size each show Hold to Pay with the header, host, total and Deny hittable, and no "Pay…"; a 2 s hold pays (`approval.respond once`). A card arriving while the composer is focused dismisses the keyboard and keeps the draft (fails without the fix); a tap or a downward swipe on the card does the same. Mac (`CrewMacUITests/PaymentWindowUITests`, CI only): a 360 pt window shows Hold to Pay with host and total hittable, light and dark, with screenshots attached.
- Measure (`-measure YES`, window content min height before → after): `chat-payment` 987 → 164, `chat-payment-punycode` 1824 → 164, `chat-payment-unverified` 539 → 164, `chat-payment-failed` and `chat-payment-loading` → 164; `chat` 226 and `chat-questions` 310 unchanged.
- Renders (#91, replacing the #72 "Pay…" ones), light and dark each: iOS portrait `renders/card-window-height-ios-portrait-*.png`, landscape `renders/card-window-height-ios-landscape-*.png`, landscape with a punycode host `renders/card-window-height-ios-landscape-punycode-*.png`, the largest accessibility text size `renders/card-window-height-ios-ax5-*.png` (all from a private iPhone 18 Pro simulator, landscape and AX5 taken from the `PaymentUITests` screenshots), and the Mac in a 360 pt window `renders/card-window-height-mac-short-*.png` (from `PaymentWindowUITests` in CI). Each shows Hold to Pay with the header, host and total on screen and no "Pay…".
