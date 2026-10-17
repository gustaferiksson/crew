# Master card from Crew: Add Card, Replace Card, Update Shops

Issue #57, superseding #54 (Copy Setup Command). Today the master card (the single `payment` item without an origin in the default profile's vault, [payments.md](payments.md#the-master-card)) is added by running a Python one-liner inside the Hermes environment. New: the inspector's **Shops** card offers **Add Card…** and **Replace…**, a native card form that sends the values once to a crew-push route, which stores them with `VaultStore.add_item` and answers with the label and last four only. After a replace, **Update Shops** re-copies the new card into the bot's shops. API shapes: [payments-contract.md](payments-contract.md#put-paymentscard).

This reverses one stated decision: the card number now passes through the client once. These lines change with this spec: [payments.md](payments.md) "Crew cannot add it", Copy Setup Command, "Remove and add the shop again to update it" and the out-of-scope "Re-copying shops"; [docs/payments.md](../payments.md) step 4's server command and step 1's "the only time a card is added by hand", plus its threat model; the contract's fixture list; a Decisions line in `docs/PLAN.md`.

## Settled constraints

- The card number, expiry, security code and name cross Crew and the dashboard API exactly once, over HTTPS, in one `PUT` body. HTTPS is to whatever terminates TLS: a reverse proxy or tunnel in front of the dashboard sees the body (stated in the threat model).
- Nothing on the device keeps them: plain `@State` in the sheet only, no `@AppStorage`, `@SceneStorage`, drafts, Keychain, pasteboard or logs; the app's `URLSession` is ephemeral (no disk cache) and a `PUT` is never cached. On Add the values are copied into the request and the fields are emptied at once; the sheet's state dies on Cancel or dismissal. The card value type is never `Codable`, only the request body dictionary is built from it.
- Crew sends the card only to an `https` server, and crew-push calls refuse every redirect (a 3xx is "Couldn't reach Hermes."), so a redirect cannot carry the body to another host or to `http`. With an `http` server the sheet says "Adding a card needs an https connection to Hermes." and Add stays disabled.
- crew-push never logs, echoes or stores the values outside the vault: the route requires `Content-Type: application/json` and reads the raw body itself (no Pydantic model, whose 422 errors echo the input), validates with regular expressions (no `int()` on raw text, whose error message quotes it), and wraps all of its work in one `except Exception` that answers `500 vault_error` without chaining or logging the exception. Errors carry a code and a reason, never a value. Only the last four leave the route.
- **Stored format**, which Hermes' fill script expects (`cc-exp` is built as `MM/` + the year's last two digits) and which keeps `stale` exact: `card_number` digits only, `exp_month` two digits, `exp_year` four digits, `cvc` digits, `cardholder_name` trimmed and left out when empty.
- **Fail closed:** the card routes refuse with `403 login_off` unless the dashboard reports its login gate on (`request.app.state.auth_required is True`, the gate the payment hooks require), on top of the dashboard login itself. Crew disables Add Card, Replace and Update Shops while `gate` is not `true`, and the existing red "Payments are off" footer says why. A card is never written when there are several cards without a website.
- **One writer at a time:** every master and copy mutation (Add Card, Replace, Update Shops, and the existing Add Shop and Remove Shop) runs under one crew-push lock (a file lock next to `payments.json`, as for `devices.json`), which re-reads the masters inside the lock, so two devices replacing at once end with exactly one card (the later one).
- **Replace** adds the new master first, then removes the old one by the id read under the lock, so a failure in between leaves two cards ("More than one card on the server"), never none. If removing the old one throws, the route tries to remove the new one again and answers `500 vault_error` either way; the Shops card reloads and shows whatever the vault holds.
- **Update Shops** re-copies every stale shop of the bot (a new item on the same origin with the current label, then the old item removed) and is idempotent: an origin that already has a fresh copy only loses its stale twins, so a run that failed half way is finished by running it again (until then the twin shows as a second row for the same host, one with "Old card"). It refuses with `409 payment_pending` while a payment for that bot is pending (state `pending` and `expires_at` still ahead, so an entry stranded by a restart never blocks it), since re-copied shops get new vault ids and the waiting fill would find "no item". A bot holding an old handle in a later turn gets "no item" from `browser_vault fill` and lists again.
- Update Shops is per bot, like the Shops card: the master is shared, so after a replace every bot's Shops card shows its own stale rows and its own Update Shops. Hand-added shop items with another card also read "Old card" and Update Shops replaces them with the master; the footnote says so.
- First card on a server without a default vault: `add_item` creates `vault/vault.key` and `vault.json.enc` (0600) as the user the dashboard runs as, which is the user Hermes runs as.
- Old crew-push (no `"card"` in `/status` `features`): no Add, Replace or Update buttons; the no-card row reads "Add one card on the server without a website. Update crew-push to add it from Crew." The Copy Setup Command button is removed everywhere (#54 superseded).

## Shops card (inspector Info tab, iPhone profile page and Mac inspector column)

Only the card row and a new Update Shops row change; shop rows, Add Shop, footers and the other states stay as in [payments.md](payments.md#shops-inspector-info-tab).

- **No card:** `creditcard.trianglebadge.exclamationmark` "No card on the server", footnote "Add the card Crew copies to each shop you add. Bots never see the number.", and **Add Card…** (`plus.circle`, borderless, like Add Shop). Add Shop stays disabled.
- **One card:** card art, "Shopping card •••• 4242" (one line, truncating the label in the middle so the last four always show), and a trailing borderless **Replace…** button (VoiceOver "Replace Card"). The default profile keeps "Kept here, never used to pay."
- **Several cards:** unchanged: "More than one card on the server", "Keep one card without a website; Crew can't tell which to use." No Add or Replace (the server would refuse with `several_cards`). Picking which card to keep is a follow-up.
- **Old card in some shops:** under the shop rows, **Update Shops** (`arrow.triangle.2.circlepath`, borderless) with the footnote "2 shops still use the old card. Update Shops copies the current card to them." (singular "1 shop still uses…"). While it runs, a small `ProgressView` replaces the button. On success the rows lose "Old card" and briefly highlight, as after Add Shop. Errors show in red under the button: `payment_pending` "Finish or deny the waiting payment first.", anything else "Couldn't update shops. Try again."; after any error the list reloads, so rows show their real state.
- **Offline or `gate` not true:** Add Card, Replace and Update Shops are disabled, like Add Shop offline.
- **Loading / couldn't load:** unchanged.

## Card sheet

Same presentation as Add Shop: iPhone `.large` sheet with a grabber (four fields and a keyboard do not fit a medium detent), Mac window sheet 400 pt wide. Title "Add Card" or "Replace Card"; **Cancel** leading, **Add** or **Replace** trailing. Add is disabled until every field is valid, while saving (a `ProgressView` in its place), offline, or with a non-https server. While saving, Cancel is disabled and the sheet cannot be swiped away (`interactiveDismissDisabled`), so the result always reaches the Shops card.

Grouped `Form`:

1. **Card Number:** prompt "1234 5678 9012 3456", formatted as typed (4-4-4-4, American Express 4-6-5), digits only kept, at most 19. **Expiry:** prompt "MM/YY", a slash inserted after the month; "MM/YYYY" from AutoFill is accepted too. **Security Code:** `SecureField`, prompt "CVC" (4 digits for American Express, 3 otherwise). **Name on Card:** prompt "Optional". iPhone uses the number pad for number, expiry and code, moves to the next field once the number is complete and valid and once the expiry is complete, and shows **Next** and **Done** above the keyboard (number pads have no Return). Every field: autocorrection off, no capitalisation except the name (words), `textContentType` `.creditCardNumber`, `.creditCardExpiration`, `.creditCardSecurityCode`, `.creditCardName`, which gives the iOS keyboard's AutoFill of saved cards and its Scan Card camera option at no extra code.
   Footer: "Crew sends the card once to your Hermes server, which keeps it encrypted. Crew doesn't store it, and bots never see the number." For Replace it adds: "Each bot's shops keep the old card until you update them in its Shops card."
2. **Label:** prefilled "Shopping card" (on Replace, the current label). Footer: "Shown in Crew and to bots with the last four digits, such as Shopping card •••• 4242."

Validation, shown under the field in red footnote text once the field loses focus, never while typing:

| Field | Rule (mirrored by the server) | Message |
|---|---|---|
| Number | 12 to 19 digits after removing spaces and dashes, passes the Luhn check | "Check the card number." |
| Expiry | month 01 to 12, year 2 or 4 digits, at most 20 years ahead | "Check the expiry date." |
| Expiry | valid through the last day of its month, on the device's calendar (the server allows one month of slack for time zones) | "This card has expired." |
| Code | 4 digits for numbers starting 34 or 37, 3 otherwise | "Enter the 3 or 4 digit code." |
| Name | at most 64 characters, no control characters | "Use a shorter name." |
| Label | 1 to 40 characters after trimming, none of `•`, `·`, `'`, line breaks or control characters (they would break or fake the `<label> •••• <last4> · <host>` the payment card parses) | "Use up to 40 letters, digits and spaces." |

Server errors show as one red line at the top of the form: `invalid_card` per reason (the same messages), `login_off` "Payments are off: this server has no dashboard login.", `several_cards` "Keep one card without a website on the server.", `vault_error` "Couldn't save the card on the server.", 5xx, 3xx or network "Couldn't reach Hermes. Try again.", offline (state not connected) "You're offline." The fields are already empty; the user types the card again (deliberate: a failed send does not keep the number around).

On success the sheet closes and the Shops card reloads `GET /payments`: the card row shows the new label and last four, and after a replace the shops show "Old card" with Update Shops.

Privacy: on iPhone, when the scene leaves `.active` (app switcher, Control Center) a full-sheet material cover with `creditcard` replaces the fields, so the app-switcher snapshot never shows them. On Mac the sheet's window gets `sharingType = .none`, which hides it from most screenshots and screen sharing (ScreenCaptureKit capture on macOS 15 and later ignores it). iOS has no public API to block screenshots. The form is also `.privacySensitive()`, which only matters where the system redacts for privacy.

## Surfaces and directions

- **Crew to crew-push:** `PUT /payments/card` (Add and Replace), `POST /payments/shops/update` (Update Shops), both behind the dashboard login. **Back to Crew:** `{card: {label, last4, problem: null}}` and `{shops: [...]}`; Crew reloads or replaces the Shops card's list.
- **Other bots' inspectors:** after a replace, their card row shows the new card on next load and their stale shops show "Old card" and Update Shops.
- **Chat payment card and push:** unchanged; they show the shop copy's label (`<label> •••• <last4>`), so a shop not yet updated keeps showing and filling the old card.
- **Bot list, push notifications, groups:** nothing changes.
- **iPhone and Mac, light and dark:** one shared SwiftUI sheet and card; system materials and secondary styles; card art unchanged.

## Not in scope

Choosing a card when there are several, Remove Card, several master cards, and updating every bot's shops in one tap.

## Tests

- **crew-push (pytest):** Add stores the normalised fields with no origin and returns label and last four; Replace adds then removes and leaves exactly one master; a failing remove rolls back; two Replaces at once leave one card; each `invalid_card` reason (bad Luhn, letters, short, bad month, expired, far future, CVC length per brand, long name, empty, long or `•`/`'`/`·` label, a non-object body, non-string fields, no JSON content type); `several_cards` writes nothing; gate off gives `403 login_off` and writes nothing; Update Shops re-copies only stale shops of that profile with fresh labels and the same origins, removes stale twins, leaves other profiles alone, refuses `payment_pending` but not for an expired pending entry, runs safely alongside Add Shop, needs the gate, `no_card`, `several_cards` and profile errors; the card number, code and name never appear in `caplog` at DEBUG, stdout, stderr, any response or any file under `plugin-data`, on every path including a `VaultError` and an unexpected exception; `401` without a login for both routes through `hermes_driver`, and a real Hermes `VaultStore` accepts the master without origin (integration test against a local Hermes source).
- **Crew unit (`CrewTests`):** `CardEntry` validation table (Luhn, Amex length and code, spaces and dashes, MM/YY and MM/YYYY, expired last month, this month valid, name and label rules), formatting of number and expiry, the request body keys and normalised values, decoding `card-set.json` and `shops-updated.json`, error codes to messages, `supportsCardEntry` from `status.json`, and a redirect refused by `paymentsCall`.
- **UI test (iOS Simulator, fixtures):** the no-card Shops card opens Add Card; a Luhn-invalid number shows "Check the card number." after moving on; an expired date shows "This card has expired."; valid values enable Add; Add records one `card` request in the fixture log (without the number) and the sheet closes; reopening shows empty fields.
- **Crew view state (`CrewTests`):** which of Add Card, Replace, Update Shops and Add Shop are enabled for each of online/offline, `gate` true/false/null and old or new crew-push; the no-card text for old crew-push; the stale count line; the sheet's blocking line (offline, http server) and whether Add is enabled.
- **Renders** (iPhone and Mac, light and dark): `inspector-shops-no-card` (Add Card), `inspector-shops` (Replace and Update Shops), `inspector-shops-empty` (login gate off: Replace disabled under the red footer), `inspector-shops-update-error` (a twin row for one host and the red Update Shops error), `add-card` (empty), `add-card-invalid` (inline errors), `replace-card` (server error line), `add-card-http` (http server line), `add-card-cover` (iPhone inactive cover).
- **Real server:** read-only `GET /status` and `GET /payments?profile=crew-test` with the current deploy. No agent sends `PUT /payments/card` to a real server: it writes the default profile's vault. After the user deploys 0.5.0, the user adds or replaces with the 4242 test card, and Update Shops can be probed on `crew-test`.
