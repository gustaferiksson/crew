# Card security code length (#97)

On 2026-10-18 Shopify kept answering "Ange CVV" because the master card, added with the old terminal one-liner, held a 4-digit security code on a Mastercard. crew-push typed it correctly every time. The card sheet and `PUT /payments/card` already refuse a wrong length since crew-push 0.5.0 (#73, [master-card.md](master-card.md#card-sheet)): 4 digits for numbers starting 34 or 37 (American Express), 3 otherwise. Two gaps remain: a card saved before that (or by hand on the server) is never flagged, and the sheet's message "Enter the 3 or 4 digit code." doesn't say which length this card needs. The speculative refill (#97 item 2) went in crew-push 0.6.7 (#98).

This spec changes: [master-card.md](master-card.md)'s Shops card "One card" line and its Code validation row, [payments-contract.md](payments-contract.md)'s `card` shape and fixture list, and a Decisions line in `docs/PLAN.md`.

## Server (crew-push 0.6.8)

- `GET /payments` adds `"code_mismatch": true | false` to `card`: `true` when the master's `cvc` is not exactly 4 digits for a card number (digits only, any other characters dropped first) starting 34 or 37, or not exactly 3 digits otherwise (an empty or missing code counts as not fitting). Only the boolean leaves the route, never the code or its length, and nothing is logged. `false` when `problem` is `missing` or `several`. `PUT /payments/card` answers `false` (it stores only a matching code). Fixtures: `payments.json` and `card-set.json` (`false`), new `payments-code-mismatch.json` (`true`).
- Old crew-push omits the key; Crew decodes it as optional and treats missing as `false`.
- Shop copies are not flagged separately: they copy the master, so after Replace Card they show "Old card" and Update Shops re-copies them, as today.
- A pending payment is not blocked or changed by the flag.

## Shops card (inspector Passwords tab, iPhone profile page, Mac inspector column)

Only the one-card row changes, and only when `code_mismatch` is `true`. Order inside the row: the "Card used for new shops" header (every server new enough to send the flag has the card vault, so the default profile's "Kept here, never used to pay." never appears together with the warning), the card art and "Shopping card •••• 4242", then the warning, then Replace Card….

- **Warning:** a `Label` at body size, "Security code doesn't match this card", with `exclamationmark.triangle.fill` in multicolor (system warning yellow, the same treatment as the no-card row's symbol), then a secondary footnote: "Shops may decline payments. Codes have 3 digits, or 4 for American Express. Replace the card to fix this." Crew only has the last four, not the brand, so the footnote names both lengths.
- The warning is not a button; Replace Card… directly below is the action, as for the no-card row and Add Card…. Replace Card… stays enabled under today's rules (online, `gate` true, new crew-push).
- **After Replace:** the sheet closes and the list reloads (`GET /payments`) as today; until it lands the row keeps showing what it had, then a matching code clears the warning and shops show "Old card" with Update Shops. A failed reload keeps the existing "Couldn't load" behaviour; the next load is correct.
- **Offline or `gate` not true:** the warning still shows (it describes the stored card); Replace Card… is disabled as today, and the red "Payments are off" footer explains a gate that is off.
- **Several cards or no card:** no warning; those rows are unchanged.
- **Long content:** the warning and footnote wrap at every Dynamic Type size and in the narrow Mac inspector column; the card label line keeps truncating at its end.
- **Accessibility:** the symbol is decorative inside the `Label`, the label text reads "Security code doesn't match this card", the footnote follows as its own element in reading order. Never colour alone: symbol and words carry it.
- **Other bots and devices:** every bot's Shops card shows it (the master is shared); another device shows it until its next load, which happens on appear as today.

## Card sheet

The code's inline error names the length this card needs: "Enter the 3 digit code.", or "Enter the 4 digit code." when the number starts with 34 or 37 (the same prefix rule as today's length check and number formatting). With no number typed yet it keeps "Enter the 3 or 4 digit code.". Timing unchanged: shown under the field once it has lost focus, never while typing; it is recomputed from the current number, so changing the number to or from 34/37 updates it. The server's `invalid_card` / `cvc` top line keeps "Enter the 3 or 4 digit code." (the reason doesn't say which length failed).

## Not changed

Chat payment card, push, receipts, bot list, the fill path, Add Shop, groups. Nothing about the code is ever shown to a bot.

## Tests

- **crew-push (pytest):** `GET /payments` with a Mastercard holding a 4-digit code gives `code_mismatch: true` and neither response nor logs contain the code; a 3-digit Visa, a 4-digit Amex and an Amex number stored with spaces give `false`/`false`/`false`; a 3-digit Amex gives `true`; missing and several cards give `false`; fixtures compared exactly. Shown failing before the route change.
- **Crew unit (`CrewTests`):** decoding `payments-code-mismatch.json` and an old response without the key; `ShopsControls.showsCodeWarning` for mismatch true/false/missing, with no card and with several; `CardEntry.problem(.cvc)` for Visa with 4 digits ("Enter the 3 digit code."), Amex with 3 ("Enter the 4 digit code.") and no number ("Enter the 3 or 4 digit code."). Shown failing before the Swift change.
- **Renders:** `inspector-shops-code-mismatch` on iPhone and Mac, light and dark; `add-card-invalid` re-rendered (light and dark) for the new message. Checked iPhone renders (the Mac capture needs Screen Recording, which the agent environment lacks; the Mac Shops card is the same SwiftUI view): `renders/card-code-length-shops-{light,dark}.png`, `renders/card-code-length-add-card-invalid-{light,dark}.png`.
- **Real server:** agents don't install plugins, so the fixtures and unit tests carry the proof; read-only `GET /payments?profile=crew-test` after the user deploys 0.6.8. No agent writes the master card.
