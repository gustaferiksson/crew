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

- `PaymentCard`: drop the `fixedSize(vertical:)` pins on its four texts (they only force wrapping that the card's vertical stack already gives when it has room). The card body (header, Pay line, rows, status) becomes `ViewThatFits(in: .vertical) { body; ScrollView { body } }` with the buttons outside it, so the scroll view is used only when the full body doesn't fit. The accessibility-size branch keeps its existing 280 pt scroll cap and bypasses `ViewThatFits` (no nested scroll views); both scroll views share one definition with `.scrollBounceBehavior(.basedOnSize)` and the system scroll indicator.
- **Paying while the body is clipped:** a 1 s hold pays without a dialog, which is only safe while the host and total are on screen. Whenever the body's scroll view is clipping content (`onScrollGeometryChange`: content taller than the visible area, in either scroll branch), the hold gesture is off and the button reads "Pay…": a click or tap opens the existing confirmation dialog, "Pay 499 kr at www.zalando.se?" with Pay and Cancel, so the host and amount are always in front of the user at the moment of paying, the way Apple Pay keeps merchant and total next to the pay action. When the window grows and the body fits again, the button is "Hold to Pay" again. VoiceOver is unchanged (its Pay action already opens the dialog).
- `ShopOfferCard`: keeps its punycode-warning pin. It wraps per word, not per character, so it adds at most a few lines to the minimum (`chat-payment-offer` measures 184 pt), and dropping it would let anti-phishing text truncate. The Add Shop sheet repeats the warning.
- Approval and question cards: no pinned texts, minimums 226 and 310 pt, the same as before this bug; unchanged. Payment notice: unchanged. The composer's own growth (draft up to its line limit, attachment tray) adds to the minimum as it does today, with or without a card.
- `Snapshot.capture()` gains a `-snapshotHeight <pt>` launch argument that sets the window's content height before the capture, for the short-window renders.
- No locked UI value changes (cards stay 560 pt max with 16 pt sides; composer, jump arrow unchanged).

## Surfaces and directions

- **Chat, Mac (main window with sidebar and inspector, and the separate chat window):** the card shows in full at normal heights (pixel-identical renders); at a short window the body scrolls and Deny / Hold to Pay stay visible above the composer; the window resizes freely while the card is up and doesn't grow when it arrives.
- **Chat, iPhone:** looks the same at normal sizes; in a short layout (landscape, keyboard up) the body scrolls instead of pushing the buttons off screen.
- **Hold to Pay, Deny, countdown, Try Again, approved state:** unchanged at normal heights. While the body is clipped, Hold to Pay becomes "Pay…" with the confirmation dialog (above); Deny, Try Again and the countdown keep working (the countdown lives in the card, so switching branches doesn't restart it; its numeric transition may skip one tick).
- **Bot list (preview, time, status, unread), push, inspector:** unchanged; nothing here touches requests or state.
- **Sender / receiver:** unchanged; the card's answers and their server calls are untouched.
- **Groups:** rooms show no payment cards (PLAN.md), unchanged.
- **Light and dark:** glass card unchanged; rendered both.

## States

- Loading, failed lookup, unverified, punycode, countdown, approved, offline (card disabled): same content, same fit rule.
- Long content (long punycode host, long FOR text up to 3 lines): wraps when there's room, scrolls inside the card when there isn't; never grows the window.
- Accessibility text sizes: unchanged 280 pt scroll cap; if it clips, the same "Pay…" rule applies (closes the same gap there).
- Resized mid-hold: if the body starts clipping during a hold, the hold is cancelled with the gesture and nothing is paid.
- VoiceOver and keyboard: the scroll view keeps every row reachable; the card's summary label (host, merchant, total) is unchanged.

## Related: #10

`layout-inspector` measures min 1240 x 202 with the inspector open: a width problem from the `.inspector` column (SwiftUI bug described in #10), not this height bug. Not fixed here.

## Tests

- Unit (`CardHeightTests`, macOS, unhosted; adds `Sources/Chat/PaymentCard.swift` to the CrewTests sources in `project.yml`): `PaymentCard` built from the recorded `approval-frame.json` request and `request-pending.json` details, hosted in `NSHostingController` at the bar's 560 pt max width. Its minimum (`sizeThatFits(in: .zero)` and the hosting view's `fittingSize` for a zero-height frame) is at most the approval card's (`ApprovalCard`, same harness) and well under its ideal height, for the verified, punycode, loading, unverified and failed states; at an ample proposal it still reports its full ideal height (no scroll at normal sizes). Cross-checked once against `-measure`.
- Measure: `-measure YES` for `chat-payment`, `chat-payment-punycode`, `chat-payment-unverified`, `chat-payment-failed`, `chat`, `chat-questions` before and after.
- Renders (macOS light and dark): `chat-payment` at the default height (unchanged) and at a short window height (body scrolls, "Pay…" shown, Deny visible), via `-snapshotHeight`. iOS `chat-payment` light and dark on a private simulator, since the view code is shared.
