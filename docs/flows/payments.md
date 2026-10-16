# Payments: approve every purchase

A bot shops in a real browser on the server. When it reaches a checkout, it asks to fill the card. Crew shows a payment card in the bot's chat and on the lock screen, and nothing is filled until the user holds **Pay**. This spec covers the whole experience on iPhone and Mac and the contract between crew-push and Crew. The research, threat model and server steps are in [docs/payments.md](../payments.md) (issue #9); where the two differ, this spec wins.

Researched against Hermes **0.22.1**. Line references are to that source.

## Settled constraints

- One **master card** in the default profile's vault, without an origin. Each shop is a copy of it bound to one exact `https` origin in the bot's own vault, made by a crew-push route. Neither Crew nor the bot ever sees the number. The only digits that leave the server are the last four, in the copy's label (as on every receipt and in Wallet).
- crew-push requires `amount`, `merchant` and `reason` on every payment fill. They are the bot's claim and are shown as such. The real cap is a low-limit virtual card.
- Payments run only in the bot's **Bot Chat** until upstream Hermes stops typed replies and `/approve` from resolving payment approvals ([plan step 5](../payments.md#5-upstream-hermes-pr-and-issue-s)).
- Crew detects a payment by the command prefix `Fill payment card '` plus a crew-push lookup by `request_id`; by `surface` once Hermes sends it.
- **No Face ID, Touch ID or LocalAuthentication.** The deliberate act is a press and hold inside Crew. No approve action outside the app.
- **Server side is crew-push only:** hooks, dashboard routes, and JSON files in `plugin-data/crew-push/` next to `devices.json`. No service, database or daemon.
- Iframe checkouts (Stripe Elements, Klarna, Adyen) are unsupported. They fail safe and the bot says so.
- The `local` terminal backend risk is accepted for now ([plan, open decisions](../payments.md#where-the-bots-shell-runs)). It is stated plainly in [Security](#security) and in the inspector.

## The moment, in one paragraph

Scout is buying winter boots. A card slides up above the composer: a small card art, **Pay www.zalando.se**, then *Zalando · Winter boots, size 43* and a large **499 kr**, with the line "Scout states the amount." The user presses and holds **Pay**; a fill sweeps across the capsule for one second with a soft haptic tick at the start; at the end a checkmark draws itself, a success haptic fires, and the card folds into a one-line receipt in the transcript: "Approved 499 kr at www.zalando.se". Scout clicks the shop's own Pay button and replies with the order number. On a locked iPhone the same request arrives as a time-sensitive notification, "Pay at www.zalando.se?", which opens straight to that card.

## Setup

### The master card

- The user adds it once on the server (`hermes vault add`, kind payment, no origin; [plan step 4](../payments.md#4-one-card-per-shop-m-about-80-python-and-150-swift-lines)). Crew cannot add it: that would put the number through the client.
- Crew learns about it from `GET /payments` (below). The bot inspector's **Shops** card shows the card row in every bot:
  - **One card:** a small card art (rounded rect, 1.586 aspect, 40 × 26 pt, a fixed dark graphite gradient with a 1 pt hairline so it reads in light and dark) followed by "Shopping card •••• 4242".
  - **No card:** "No card on the server" and the footer "Add one card on the server without a website. Crew copies it to each shop you add." A **Copy Setup Command** button copies `hermes vault add` (no host or credentials in it). Add Shop is disabled.
  - **Several cards without a website:** "More than one card on the server" and "Keep one card without a website; Crew can't tell which to use." Add Shop is disabled.
  - **Card changed** (a shop's copy no longer matches the master): the affected shop rows show "Old card" in orange and the card row offers **Update Shops**, which re-copies them (`POST /payments/shops/update`).
- In the default profile's own inspector the card row adds "Kept here, never used to pay." The master never appears as a shop.

### Shops (inspector, Info tab)

A new card titled **Shops** after Capabilities and before Other Conversations, on iPhone (profile page) and Mac (inspector column). Same `Card` component as its neighbours.

- **Rows:** one per shop: the host in body text, a secondary line "Added 12 Oct" or "Last paid 14 Oct" (from the payments log). A host starting `xn--` or containing `.xn--` gets an orange `exclamationmark.triangle.fill` and the secondary line "Unusual address: check the spelling".
- **Empty (no shops):** "Scout can't pay anywhere yet." The bot is payment-enabled exactly when it has at least one shop; there is no separate switch to forget about.
- **Add Shop…** row (`plus.circle`) opens the Add Shop sheet.
- **Remove:** swipe to delete on iPhone, a context menu Delete and the Delete key on Mac. No confirmation alert: removing is undoable by adding the host again (HIG alerts: no alert for common, undoable deletes). The row animates out after the route answers; on failure it stays and an inline error shows under the card.
- **Recent Payments:** the last three log entries for this bot (see [History](#history)) and **Show All** when there are more.
- **Footers**, in order, only when true:
  - "Scout pays only on these sites, and asks you every time." (always, when there is a shop)
  - Browser toolset off: "Turn on Browser in Capabilities so Scout can shop." with the Capabilities row as the way there.
  - `terminal.backend` is `local` (from `GET /payments`): "Bots on this server run commands next to the card, so a misbehaving bot could read it. Keep the card's limit low."
  - Dashboard login off (`gate: false`): "Payments are off: this server has no dashboard login." in red. Add Shop stays enabled (shops are harmless), fills are blocked server side.
- Offline: the last loaded list stays, Add and Remove are disabled with the usual offline treatment. Loading: a small `ProgressView` in the card, as other cards do.

### Add Shop sheet

- iPhone: a sheet at `.medium` with a grabber; Mac: a window sheet 360 pt wide. Title "Add Shop", **Cancel** leading, **Add** trailing (disabled until valid).
- One field, "Website", placeholder `www.zalando.se`, URL keyboard, no autocorrect or capitalisation. Pasting a full checkout URL works.
- Live line under the field: "The card will fill only on **https://www.zalando.se**." The host is the largest text in the sheet. For an `xn--` host the line turns orange: "This address uses special characters and could imitate another site."
- A hint under it: "Use the address shown at checkout. www.zalando.se and zalando.se are different sites."
- Validation is the server's (the sheet only previews it); errors come back inline under the field in red, from the route's codes: not https, an IP address, localhost or a single-label name, a path-only entry, already a shop.
- After Add: the sheet closes, the new row appears with a short highlight. When the sheet was opened from the inline offer (below), Crew then tells the bot (see [No card for this shop](#no-card-for-this-shop)).

## The shopping turn

What the chat shows while the bot shops. Everything is the existing transcript, plus three small additions.

1. The work log shows the browsing as today ("Opened zalando.se", "Browsed"). `browser_vault` gets its own style: icon `creditcard`, verb "Checked cards" for `list`, "Card" for `fill` with the subject "at www.zalando.se". Expanding a fill row shows the args (`amount`, `merchant`, `reason`, `handle`) and the result as for any tool.
2. While the approval is pending, the composer bar holds the **payment card** (next section) in the place approval cards use (560 pt max, 16 pt sides, the locked values in PLAN.md).
3. After the decision, the turn shows a **receipt row**: a single centred secondary line in the work-log style with a leading `creditcard` symbol, outside the collapsed work log so it stays visible:
   - "Approved 499 kr at www.zalando.se" (green check symbol)
   - "Denied 499 kr at www.zalando.se" (red)
   - "Payment request expired" (secondary)
   - "Payment request cancelled" (Stop, or the session closed)
   - "Approved, but the card wasn't filled: card fields not found" (orange), see [Results](#results)
   - Tapping the row toggles one more line with "Zalando · Winter boots, size 43 · 14:02".
   The row is derived from the `browser_vault` fill call in the turn and its decorated result (`crew_payment`, see the contract), so it survives reloads, history paging and cold launches with no extra request.
4. The bot list row: status "Wants to pay" (a new `WaitingKind.payment`, same style as "Needs approval") while the payment card is open. Preview, time and unread are unchanged; the bot's reply after the purchase updates them as any reply does.

## The approval card

### Layout

Top to bottom, inside the existing glass card shape (`.glassEffect(in: .rect(cornerRadius: 28))`, 16 pt padding):

- **Header:** the bot's 20 pt avatar and "Scout wants to pay" in subheadline semibold. Trailing, only in the last 60 seconds: "0:45" in monospaced digits, secondary, turning orange under 15 seconds.
- **Merchant line:** "Pay" in title3 secondary, then the host in title2 semibold, on one line, wrapping by character only if it must. The host comes from the approval's `command` (the vault item's bound origin), which is the one fact Hermes enforces. An `xn--` host gets the orange warning line under it, as in the sheet.
- **Details**, label/value rows like the Apple Pay sheet (labels caption uppercase secondary, values body):
  - CARD: the card art (24 × 16 pt) and "Shopping card •••• 4242"
  - FOR: "Zalando · Winter boots, size 43" (merchant, then reason; up to 3 lines)
  - a hairline divider
  - TOTAL: "499 kr", title2 semibold, trailing
- **Claim line:** footnote secondary: "Scout states the amount and the shop. The card fills only on www.zalando.se." This is the honest answer to "the charge can differ" and is never hidden.
- **Buttons:** **Deny** (glass, `role: .destructive`) leading and **Pay** (glass prominent, the hold control) trailing, both flexible width, capsule shape, the same row layout as Allow Once/Deny today.

Details load from crew-push by `request_id` (contract below). While they load (normally under 200 ms) the details rows show redacted placeholders and Pay is disabled. If they cannot load:

- **crew-push supports payments but the request is unknown** (404 `unknown_request` after the retries in the contract): this is not a vault fill (an MCP server can send the same text), so Crew shows the ordinary approval card with the raw command and only Allow Once and Deny.
- **Network error:** the details area says "Couldn't load the amount." with **Try Again**; Pay stays disabled, Deny works. Approving without the amount is what this feature exists to prevent.
- **crew-push missing or older than 0.4.0** (`/status` has no `payments` feature): the ordinary approval card, with Allow for Session and Always Allow hidden for prefix matches because Hermes treats them as a single fill anyway.

### Hold to Pay

The deliberate act that replaces a biometric. It guards against a stray tap in the bar where the user is typing; it is **not** a security boundary (see [Security](#security)).

- **Press:** the capsule scales to 0.97 and a lighter fill sweeps leading to trailing over **1.0 s**. A light impact haptic on touch down (`.sensoryFeedback(.impact(weight: .light))`, iOS).
- **Release early:** the fill springs back (0.25 s) and the label reads "Hold to Pay" for 2 s. Nothing is sent.
- **Complete:** a `.success` haptic, the label is replaced by a `checkmark` drawn with `.symbolEffect(.drawOn)` and "Approved". Crew sends the answer (contract: `approval.respond` with the `request_id`). The card stays 0.8 s in the approved state, then collapses away (`.smooth`), and the receipt row appears in the transcript when the result lands.
- **Tap** (a press shorter than 0.3 s), **keyboard** (Space or Return with focus on Mac or with a hardware keyboard), **VoiceOver, Voice Control and Switch Control** activation: a confirmation dialog anchored to the button, "Pay 499 kr at www.zalando.se?" with **Pay** and **Cancel**. One path for everyone who cannot or did not hold; never a silent approval from a single tap.
- **Return in the composer** never reaches the card; the card's buttons have no keyboard shortcut.
- **Answer fails** (socket closed mid-send, `resolved: 0`): the approved state reverts to the card with an inline error under the buttons ("Couldn't reach Hermes. Try again." or "Already answered or expired."), then the state from the route decides what shows.
- **Reduce Motion:** no scale and no spring; the fill is a plain linear progress, the check appears without the draw effect.
- **Mac:** the same with a mouse or trackpad press; the haptics are omitted (no `NSHapticFeedbackManager` for this, as Apple Pay on Mac has none either).

### Deny

A plain tap, no confirmation: denying is safe and is what an unsure user should do. The card collapses, the receipt row reads "Denied …". The bot is told "The user denied this payment. Do not retry; ask what they want instead." (crew-push rewrites Hermes' generic text, see the contract.)

### Expiry

Hermes waits `approvals.timeout` (default 300 s, from queueing) and then declines. In the last 60 s the header shows the countdown. At zero the card collapses, the receipt row reads "Payment request expired", and the bot is told nobody answered and not to retry until the user asks. The push for it is withdrawn on every device (`payment_resolved`).

## Push

- **Kind `payment`**, category **`CREW_PAYMENT`**, `interruption-level: time-sensitive`, priority 10, `apns-expiration` at the request's `expires_at`, thread `profile.<bot>` so it groups with the bot's other notifications.
- **Content:** title "Pay at www.zalando.se?", subtitle "Scout · Shopping card •••• 4242", body "499 kr · Zalando · Winter boots, size 43". With previews off on the device (crew-push `prefs.previews`): title the bot's name, body "Wants to pay". The category's `hiddenPreviewsBodyPlaceholder` is "Payment request" for the iOS "when unlocked" setting.
- **Tap:** opens Crew to that bot's chat with the card up (cold launch included; the card arrives with `session.resume` `open_requests`).
- **Actions: Deny only** (`.destructive`, symbol `xmark`, no `.authenticationRequired`, no `.foreground`). Decided:
  - No **Approve** action. Without Face ID anyone holding a locked phone could pay, and on Apple Watch the notification double tap picks the first non-destructive action. Approval happens only in the app, with the hold.
  - **Deny** fails safe and saves a trip into the app, so it earns its place. A passer-by denying is harmless. The handler calls `POST /payments/requests/{id}/deny` with the stored login and refuses to act without a `request_id`. On failure it posts a local notification: "Couldn't reach Hermes. Open Crew to answer."
  - Apple Watch shows the mirrored notification with Deny; double tap does nothing because there is no non-destructive action.
- **Resolved anywhere** (approved, denied, expired, cancelled; on this device, another device, the TUI): crew-push sends a background `payment_resolved` push and every device removes the delivered `payment` notification for that `request_id`. iOS needs the existing `remote-notification` background mode; Mac handles it in `didReceiveRemoteNotification`.
- **Foreground:** while the app is active on that bot's chat no banner (as for every kind); on another chat a banner whose tap switches to the bot.
- Push is the only extra surface. No Live Activity, no widget.

## Results

What the bot gets back, what Crew shows, what the bot should say. "Card" means the payment card in the composer bar, "row" the receipt row.

| Case | Server signal | Crew shows | Bot |
|---|---|---|---|
| Filled | fill `success: true` and `cc-number` among `fields`; `crew_payment.fill: "filled"` | card collapses, row "Approved 499 kr at …" | clicks the shop's Pay, reports the outcome or order number; told not to tick "save card" |
| Denied | `payment_declined`, `crew_payment.state: "denied"` | row "Denied …" | "OK, I won't pay." Further fills blocked until the user's next message |
| Expired | `payment_declined`, state `expired` | card leaves at zero, row "Payment request expired" | says the request expired; same block |
| Cancelled | state `cancelled` (Stop, session closed, `notify_failed`) | card leaves, row "Payment request cancelled" | nothing (interrupted) or a short note |
| Origin moved after approval | `origin_mismatch` or `origin_changed`, `crew_payment.fill: "not_filled"` | row "Approved, but the card wasn't filled: the page left www.zalando.se" | explains; may navigate back and ask again (new card) |
| Card fields not found | "No payment form fields…" or success without `cc-number`, `fill: "not_filled"`, `fill_error: "no_fields"` | row "Approved, but the card wasn't filled: card fields not found" | says this checkout likely uses a payment frame Crew can't fill yet (iframe) |
| No card for this shop | crew-push block or `list` decoration with `missing_shop` | **offer card** (below), no payment card | "I don't have a card for www.zalando.de. Add it in Crew?" |
| Details missing | crew-push block `missing_details` | nothing new (a failed tool row in the work log) | retries with `amount`, `merchant`, `reason` |
| Outside Bot Chat | block `not_bot_chat` | in a group room or another session: the bot's explanation only | "I can only pay from my chat in Crew." |
| Another payment pending | block `one_at_a_time` | nothing new | waits for the first answer |
| Dashboard login off | block `gate_off` | the bot's explanation; Shops footer in red | "Payments are off on this server." |
| No master card | copy route `no_card` | offer card's Add is replaced by "Add a card on the server first" linking to Shops | n/a |
| crew-push or Hermes error | route 5xx, `eval_failed`, `supervisor_required`, hook exception (blocks, fail closed) | details: "Couldn't load the amount" + Try Again; fill errors: row "Approved, but the card wasn't filled: <short reason>" | explains briefly |

### No card for this shop

The bot is on a checkout whose origin has no shop. crew-push sees it in two places, both from the real page origin (never from the bot's words): a `list` call on a page with card fields (Hermes' own payment probe) and a `fill` whose handle is bound elsewhere (blocked before any approval, so the user never approves a fill that cannot happen).

Crew shows an **offer card** in the composer bar when the latest turn is finished and its last `browser_vault` result carries `crew_payment.missing_shop` for an origin that is still not a shop:

- "Scout needs a card for **www.zalando.de**" with the `xn--` warning when it applies.
- **Not Now** (glass) dismisses it for this turn. **Add Shop…** (glass prominent) opens the Add Shop sheet with the host filled in; the user still taps Add.
- After Add, Crew sends a hidden prompt (`display_kind: "hidden"`, as `sendHidden` does today): "I added https://www.zalando.de to your shops. Continue the purchase." and the transcript shows a centred secondary system line "Added www.zalando.de to Shops". The bot continues and the normal payment card follows.

## iPhone and Mac

- **iPhone:** card in the composer bar of the chat; the keyboard is dismissed when the card appears so the bar is visible; Shops on the profile page; Add Shop as a medium sheet; lock screen and Notification Center push with Deny; haptics as above.
- **iPad:** as iPhone; the card keeps its 560 pt max in regular width; the sheet is a form sheet.
- **Mac:** card in the chat column; Shops in the inspector column; Add Shop as a window sheet; banner and Notification Center with Deny under the banner's options; no haptics. When the bot's chat is not the selected one, the bot list row says "Wants to pay" and the banner's click selects it. The confirmation dialog is the keyboard path.
- **Both:** the card, the rows and the sheet use system materials and secondary styles; checked in light and dark. The card art's gradient is fixed and has its own hairline, so it reads on both.

## Other states

- **Offline:** the card stays visible with its details (already loaded) and Pay is disabled, with the composer's offline line (the existing 2 s delay). Deny is disabled too: both need the socket. The server expires the request on its own; on reconnect `session.resume` drops the card if it is gone.
- **Cold launch from the push:** Crew selects the bot, opens the chat, the card arrives with `open_requests`. If the request already ended (state from `GET /payments/requests/{id}`), a notice takes the card's place: "This payment request expired at 14:07." (or "was denied on another device", "was approved on another device") with **OK**. Never an empty chat with no explanation.
- **Several bots at once:** each bot's chat has its own card and the bot list shows "Wants to pay" on each; each push is its own notification (collapse id per request). Within one bot, crew-push allows one pending payment per session, so a chat never stacks payment cards.
- **Answered on another device or client** (the other Crew device, the TUI, Hermes Desktop): Hermes sends `request.cancel {reason: "resolved"}` because Crew answers payments with `approval.respond` (below). The card collapses into a notice for 3 s: "Approved on another device" or "Denied on another device" (state from the route), then the receipt row arrives with the result.
- **Stop while the card is up:** Hermes cancels the request (`request.cancel`, reason `interrupted`); the card leaves and the row reads "Payment request cancelled".
- **The bot is deleted or its chat compressed while pending:** the request is cancelled with the session (`approval.cancelled`); the card leaves.
- **Long content:** host wraps by character (never truncated: the host is the fact), merchant and reason clamp to 3 lines inside the card (the full text is in the expanded work-log row), amount is capped at 32 characters server side.
- **Large Dynamic Type:** the details rows stack label above value; the card scrolls inside the bar when taller than half the screen.
- **Group rooms:** crew-push blocks fills outside Bot Chat, so a room only shows the bot's explanation. A payment request that still reaches a room (crew-push missing) renders as the ordinary approval card.

## History

- **Receipt rows** in each chat (above) are the in-context history.
- **Recent Payments** in the Shops card, and **Show All** as a sheet (iPhone) or window sheet (Mac) listing up to 50 entries for this bot, newest first, grouped by day like Wallet: host and amount on the first line, "Winter boots · Approved · 14:02" on the second, a leading state symbol (`checkmark.circle.fill` green, `xmark.circle.fill` red, `clock` secondary, `exclamationmark.triangle.fill` orange for "not filled"). Rows are read only; there is nothing to edit.
- Empty: "No payments yet."
- Source: crew-push's `payments.json` log (the server keeps the last 200 across all bots). Crew stores nothing.
- No receipt document: the shop's own confirmation and the bank statement are the receipts. The log keeps the bot's stated amount next to the time, which is what the user needs to compare with the statement.

## Accessibility

- The card is one container with the element order header, merchant, details, claim, buttons. Its label reads "Payment request from Scout. Pay 499 kronor at www.zalando.se. Zalando, Winter boots, size 43. Card ending 4242. Scout states the amount." The amount uses the bot's string as is.
- **Pay** is labelled "Pay", hint "Double-tap to confirm, or touch and hold to pay." VoiceOver activation opens the confirmation dialog; the custom action "Pay" does the same. Deny is labelled "Deny payment".
- The countdown is announced once at 60 s and once at 15 s with `AccessibilityNotification.Announcement`, never every second.
- The `xn--` warning is part of the host's label ("Unusual address, check the spelling").
- Receipt rows are buttons labelled by their text; the expanded line is part of the label once open.
- Dynamic Type everywhere (no fixed font sizes); minimum 44 pt targets on iPhone; colours are never the only signal (every state has a symbol and words).
- Full Keyboard Access and the Mac keyboard reach Deny and Pay by Tab; Pay opens the dialog with Space or Return.
- Reduce Motion handled as above; Reduce Transparency falls back to the system's opaque glass.

## Security

The checks the reviewer asked for, and where each is handled.

| Threat | Handling |
|---|---|
| **Approval spoofing** by an MCP elicitation or tool that sends the same `Fill payment card '…' on …` text | Crew shows the payment card only when crew-push knows the `request_id`, and crew-push records only approvals with `surface == "vault-payment"` that follow its own `pre_tool_call` on `browser_vault fill`. Unknown requests get the ordinary card with the raw command. |
| **The bot approving its own payment** | A bot cannot answer through Crew. Over HTTP it would need the dashboard session: on a dashboard **without** the login gate, `GET /` hands out the session token to any local process (`web_server_dashboard.py:165-168`), which also opens `/api/ws` and `approval.respond`. crew-push therefore blocks every payment fill unless the dashboard reports `auth_required` (the login Crew uses on mainframe), fail closed until it has seen that. Under the `local` backend a bot can still read the server's files, which defeats this and the vault alike: that is the accepted risk below. |
| **Replayed approval** | Crew answers with `approval.respond {request_id}`; the id is a one-time `uuid4().hex`, and a second answer returns `resolved: 0`, which changes nothing. There is no approve route and no approve push action; the deny route can only deny a pending request. Pushes carry ids, never capabilities. |
| **Look-alike host** | Shops are `https` only, exact origin, lower-cased, no IPs or localhost. `xn--` hosts are flagged in the sheet, the shop list, the card and the offer. The offer's host comes from the page origin crew-push reads, not from the bot's text, and adding still takes a deliberate Add in a sheet that shows the host largest. A typo'd shop is the user's to catch; the card shows the host on every payment. |
| **Amount differs from the charge** | Not preventable here: Hermes approves the fill, not the cart. The card labels the amount as the bot's claim every time, the log keeps the claim for comparison with the statement, and the issuer's low limit is the cap. |
| **Display spoofing** in amount, merchant or reason | crew-push strips control and format characters (Unicode Cc and Cf: bidi overrides, zero-width), collapses whitespace, caps lengths (32/64/140), and requires a digit in `amount`. Crew renders them as plain `Text`, no Markdown or links. |
| **Nagging** (approval fatigue) | One pending payment per session; after a deny or expiry, fills are blocked until the user's next message. |
| **Typed replies and `/approve`** on other platforms | Payments run only in Bot Chat, which no messaging platform drives. Until upstream lands, another client attached to the same Bot Chat (TUI, Desktop) can still answer with `session`, `always` or `/approve`; Hermes treats each as one fill. |
| **request_id recovery race** | `pre_approval_request` carries no `request_id`; crew-push takes the newest pending entry in that session whose `command` equals the hook's `command`. With one pending payment per session the match is unique. |
| **Coalescing** | Hermes coalesces identical pending commands and lets a follower adopt `session`/`always`/`deny`. One pending payment per session means there is never a follower. |
| **Wrong tab** | Hermes may fill any open tab on the bound origin with card fields (`_focus_bound_origin`). Same origin, so same shop; accepted. |
| **Card read back after a fill, saved cards, iframes** | As in [the plan's threat model](../payments.md#threat-model). Iframes fail safe ("card fields not found"); partial fills without `cc-number` count as not filled. |
| **The `local` backend** | Every bot's shell runs next to every `vault.key`, so a misled bot could decrypt the card or forge its way past the gate. Accepted now; the inspector says so; the cure is the `docker` backend for every bot. Worst case is one month of the card's limit. |
| **Lock screen content** | The push shows host, amount, merchant and reason. Previews off hides them; never the card number (crew-push never reads it for a push). |

## Contract (crew-push 0.4.0 and Crew)

All routes are under `/api/plugins/crew-push/`, behind the dashboard login like the existing ones (Crew's cookie). Bodies are JSON. Errors use FastAPI's shape with a code: `{"detail": {"code": "<code>", "message": "<one line for logs>"}}`. Crew maps codes, never messages, to UI text. Timestamps are Unix seconds (float). `profile` is a Hermes profile id (`^[a-z0-9][a-z0-9_-]{0,63}$`).

The JSON below is canonical; PR A commits each example as a fixture in `Tests/fixtures/payments/` and both test suites decode them.

### `GET /status` (existing, extended)

Adds `"features": ["payments"]` and `"gate": true|false|null` (null: the dashboard has not reported yet). Crew uses `features` to decide whether to ask for payment details at all.

### `GET /payments?profile=scout`

Everything the Shops card needs in one call.

```json
{
  "card": {"label": "Shopping card", "last4": "4242", "problem": null},
  "shops": [
    {"id": "vault_3f9a1c2b7d4e", "origin": "https://www.zalando.se", "host": "www.zalando.se",
     "created_at": 1760600000.0, "last_paid_at": 1760610000.0, "stale": false, "punycode": false}
  ],
  "recent": [ <payment entry>, ... ],
  "terminal_backend": "local",
  "gate": true
}
```

- `card` is `{"label": null, "last4": null, "problem": "missing" | "several"}` when there is no usable master. `last4` is computed from the master's secret in the route; the number itself never leaves the function.
- `shops`: the profile's vault items with `kind == "payment"` and an origin. `stale`: the copy's secret differs from the master's (compared server side). `punycode`: any host label starts with `xn--`.
- `recent`: this profile's log entries, newest first, at most 50.
- `terminal_backend`: the profile's resolved `terminal.backend` (`local` when unset).
- Errors: `400 invalid_profile`, `404 unknown_profile`.

### `POST /payments/shops`

Request `{"profile": "scout", "site": "https://www.zalando.se/checkout?step=2"}`. The route lower-cases, takes scheme and host only, forces `https`, refuses ports other than 443, IP literals, `localhost`, single-label hosts and an `http://` entry (`invalid_site` with `reason`). It reads the master from `get_default_hermes_root()/vault`, then `VaultStore(get_profile_dir(profile) / "vault").add_item(kind="payment", label="<master label> •••• <last4> · <host>", origin="https://<host>", secret=<master secret>)`.

- `201` → `{"shop": <shop>}`
- `400 invalid_site` with `"reason": "not_https" | "ip_address" | "localhost" | "no_host" | "port"`
- `409 duplicate_shop`, `409 no_card`, `409 several_cards`, `404 unknown_profile`

### `DELETE /payments/shops/{id}?profile=scout`

Removes one shop (only a payment item with an origin). `200 {"removed": true}`; `404 unknown_shop`.

### `POST /payments/shops/update`

Request `{"profile": "scout"}`. Re-copies every stale shop (add the new copy, then remove the old; ids change). `200 {"updated": 2, "shops": [...]}`; `409 no_card`, `409 several_cards`.

### `GET /payments/requests/{request_id}`

The payment entry for one approval. Crew calls it when an approval arrives whose `command` starts with `Fill payment card '`, and when it opens from a push.

```json
{
  "request_id": "5f0c3e9a2b7d4c18a6e1f20b9d3c7a54",
  "profile": "scout",
  "session_id": "20261016_101512_ab12cd",
  "origin": "https://www.zalando.se",
  "host": "www.zalando.se",
  "card_label": "Shopping card •••• 4242",
  "amount": "499 kr",
  "merchant": "Zalando",
  "reason": "Winter boots, size 43",
  "state": "pending",
  "fill": null,
  "fill_error": null,
  "created_at": 1760609940.0,
  "expires_at": 1760610240.0,
  "decided_at": null
}
```

- `state`: `pending | approved | denied | expired | cancelled` (Hermes' `once/session/always` → approved, `deny` → denied, `timeout` → expired, `cancelled`/`notify_failed` → cancelled).
- `fill`: `null` until the tool returns, then `filled | not_filled`; `fill_error`: `null | no_fields | origin_mismatch | origin_changed | error`.
- `card_label` drops the ` · <host>` suffix.
- `404 unknown_request`. The entry is written in `pre_approval_request`, which Hermes fires right after queueing the request and around the moment it sends the `approval` frame, so Crew retries a 404 three times, 300 ms apart, before treating the request as not a payment.

### `POST /payments/requests/{request_id}/deny`

For the push action. Calls `tools.approval.resolve_gateway_approval(session_key, "deny", request_id=…)` in the dashboard process (where Crew's sessions run).

- `200 {"state": "denied"}`
- `409 not_pending` with `"state"` (already answered or expired), `404 unknown_request`
- `409 not_in_process` when the approval queue is not in this process (`plugins.isolation: host`); the push handler then shows its "Open Crew to answer" notification.

### Answering in the app

Crew answers a **payment** with the RPC `approval.respond {"session_id": <runtime id>, "choice": "once" | "deny", "request_id": <32 hex>}` instead of the server-request response frame, because only this path makes Hermes send `request.cancel {reason: "resolved"}` to every other attached client (a response frame leaves other clients' cards up, `server_requests.py:284`). Result `{"resolved": 1}` is success; `{"resolved": 0}` means already answered or expired; error `4001` means the session is gone. Other approvals keep the response frame. Crew never sends `session` or `always` for a payment.

### Hooks (server behaviour behind the contract)

- **`pre_tool_call`** on `browser_vault` with `action == "fill"` and a handle whose item kind is `payment` returns `{"action": "block", "message": <JSON string>}` with `{"success": false, "error_type": "crew_<code>", "error": "<what the bot should do>"}`, checked in this order:
  1. `gate_off`: the dashboard has not reported `auth_required: true`. Any crew-push route request records `request.app.state.auth_required` in the module; Crew calls `/status` on every connect.
  2. `not_bot_chat`: the session is not the profile's Bot Chat (`is_bot_chat`).
  3. `one_at_a_time`: a payment in this session is pending.
  4. `after_decline`: the last payment in this session was denied or expired and no user message has arrived since (`pre_llm_call` with a non-agent user message clears it; Crew's hidden "added a shop" prompt counts).
  5. `missing_details`: `amount`, `merchant`, `reason` missing, empty after cleaning, too long, or `amount` without a digit. The message names the three args and gives an example.
  6. `no_shop_card`: the current page origin (read the way Hermes reads it, `window.location.href` through the supervisor) differs from the item's origin; adds `"crew_payment": {"missing_shop": "<page origin>"}`. Skipped when the origin cannot be read; Hermes' own check still refuses the fill.
  Otherwise it remembers the cleaned claim by `tool_call_id` and returns nothing. Any exception blocks. Hermes passes unknown args through to the tool (`coerce_tool_args` skips them); if a provider drops them, the plan's schema-override fallback applies.
- **`pre_approval_request`** with `surface == "vault-payment"`: looks up the claim by `tool_call_id`, recovers `request_id` (newest pending entry for `session_key` whose `command` equals the hook's), computes `expires_at` from `approvals.timeout`, writes the log entry with `state: "pending"`, and sends the `payment` push. Without a claim (crew-push loaded after the call started) it writes nothing and Crew shows the ordinary card.
- **`post_approval_response`** with `surface == "vault-payment"`: sets `state` and `decided_at`, then sends `payment_resolved` to every device.
- **`transform_tool_result`** on `browser_vault`:
  - `fill` on a payment item: parses Hermes' result and returns it with `"crew_payment": {"request_id", "state", "fill", "fill_error"}` added, and replaces `error` for `payment_declined` by state (denied: do not retry, ask; expired: say it expired, do not retry until asked; cancelled: stop). A success without `cc-number` in `fields` becomes `"success": false`, `fill_error: "no_fields"` with "Card fields weren't found; this checkout probably uses a payment frame, which can't be filled. Tell the user." A real success gets "Click the shop's pay button. Never tick save card or remember card." Updates `fill` in the log.
  - `list`: when the current page matches Hermes' payment field probe and its origin has no payment item in this profile, adds `"crew_payment": {"missing_shop": "<origin>"}` and a `hint` telling the bot to ask the user to add the shop in Crew.
  - The block message from `pre_tool_call` reaches the transcript as the tool result; PR A records its exact wrapped shape in a fixture, and Crew decodes a JSON object either at the top level or inside an `error` string.
- **Log:** `plugin-data/crew-push/payments.json`, a JSON list, newest last, at most 200 entries, written with the same lock and atomic replace as `devices.json`. No card data beyond `last4` inside `card_label`.

### Push payloads

`payment` (alert):

```json
{
  "aps": {
    "alert": {"title": "Pay at www.zalando.se?", "subtitle": "Scout · Shopping card •••• 4242",
              "body": "499 kr · Zalando · Winter boots, size 43"},
    "sound": "default", "thread-id": "profile.scout", "category": "CREW_PAYMENT",
    "interruption-level": "time-sensitive"
  },
  "crew": {"v": 1, "kind": "payment", "install_id": "9f2c41d07ab35e11", "profile": "scout",
           "session_id": "20261016_101512_ab12cd", "event_id": "5be0c2a91f7d3e44",
           "request_id": "5f0c3e9a2b7d4c18a6e1f20b9d3c7a54", "expires_at": 1760610240.0}
}
```

Headers: `apns-push-type: alert`, `apns-priority: 10`, `apns-expiration: <expires_at>`, `apns-collapse-id: payment.<sha256(request_id)[:16]>`. Pref: `approvals`. Previews off: title the bot name, no subtitle, body "Wants to pay".

`payment_resolved` (background, to every device):

```json
{"aps": {"content-available": 1},
 "crew": {"v": 1, "kind": "payment_resolved", "install_id": "9f2c41d07ab35e11", "profile": "scout",
          "request_id": "5f0c3e9a2b7d4c18a6e1f20b9d3c7a54", "state": "approved"}}
```

Headers: `apns-push-type: background`, `apns-priority: 5`, `apns-expiration: now + 3600`, `apns-collapse-id: payment-resolved.<sha256(request_id)[:16]>`. Crew removes delivered notifications whose `crew.request_id` matches.

The generic `approval` push is not sent for a payment (crew-push sends `payment` instead).

### Error codes (summary)

| Where | Code | Crew shows |
|---|---|---|
| routes | `invalid_profile`, `unknown_profile` | inline "Couldn't load shops." |
| `POST /payments/shops` | `invalid_site` + `reason` | under the field: "Use an https address." / "Use a name, not an IP address." / "That isn't a public website." / "Enter a website." / "Use the standard https port." |
| | `duplicate_shop` | "www.zalando.se is already a shop." |
| | `no_card`, `several_cards` | the card row states (Setup) |
| `DELETE` | `unknown_shop` | the row disappears (already gone) |
| `GET /payments/requests/{id}` | `unknown_request` | ordinary approval card after retries |
| `POST …/deny` | `not_pending`, `unknown_request`, `not_in_process` | push handler: no-op, no-op, local "Open Crew to answer" |
| block messages | `crew_gate_off`, `crew_not_bot_chat`, `crew_one_at_a_time`, `crew_after_decline`, `crew_missing_details`, `crew_no_shop_card` | only `crew_no_shop_card` drives UI (the offer); the rest show as failed tool rows and the bot's words |
| `approval.respond` | `resolved: 0`, `4001`, `5004` | "Already answered or expired.", the card leaves, "Couldn't reach Hermes. Try again." |
| any 5xx or network | | "Couldn't load the amount." + Try Again (card), "Couldn't load shops." (inspector) |

## Build: two parallel PRs

The contract fixtures in `Tests/fixtures/payments/` are written first, in PR A's first commit, and copied unchanged into PR B's branch so B never waits for A.

**PR A: crew-push 0.4.0** (`server/crew-push`, `pages/`)
- `crew_push/payments.py`: log store, claim cleaning, site normalisation, shop copy and staleness.
- `crew_push/hooks.py`: the payment branch of `pre_tool_call`, `pre_approval_request`, new `post_approval_response` and `transform_tool_result`, the `after_decline` reset in `pre_llm_call`, kinds `payment` and `payment_resolved` in `build`.
- `dashboard/plugin_api.py`: the routes, `features` and `gate` in `/status`, recording `auth_required`.
- `plugin.yaml`, `dashboard/manifest.json`, `crew_push/__init__.py`: 0.4.0 and `provides_hooks`.
- `pages/checkout-test.html` and `pages/checkout-iframe-test.html` (tests below).
- `docs/push.md`: one line per new kind and route.

**PR B: Crew** (`Sources`, `Tests`)
- `Sources/Chat/RequestCards.swift`: `PaymentRequest` (parsed from the command: label, last4, origin, host, punycode), `PaymentCard`, the hold control, the confirmation dialog, `OfferCard`.
- `Sources/Chat/ChatSession.swift`: detail fetch with retries, `approval.respond` for payments, ended-request notice, hidden prompt after adding a shop.
- `Sources/Chat/WorkLog.swift`, `Transcript.swift`: `browser_vault` style and the receipt row from `crew_payment`.
- `Sources/BotStore.swift`, `BotsView.swift`: `WaitingKind.payment`, "Wants to pay".
- `Sources/Push/PushCenter.swift`, `AppDelegate.swift`: `CREW_PAYMENT` with Deny, the deny handler, `payment_resolved`, `PushRoute.requestID`.
- `Sources/Inspector/Shops.swift` (new), `BotInspector.swift`: Shops card, Add Shop sheet, Show All.
- Snapshots in `ChatFixtures.swift` and `InspectorSnapshots.swift`; `docs/PLAN.md` Decisions lines (hold to pay, payment card, Shops).

## Tests

- **Contract fixtures** (`Tests/fixtures/payments/`): every route response and error above, both pushes, a decorated fill result per outcome, the wrapped block message. crew-push tests assert its output equals them; Crew tests decode them.
- **crew-push (pytest):** each block code in order and the allow path; claim cleaning (bidi and zero-width stripped, caps, digit rule); `request_id` binding with a dangerous-command approval pending in the same session; log states for every `choice`; `transform_tool_result` per outcome including a success without `cc-number`; `list` `missing_shop`; site normalisation table (path, query, uppercase, `http`, IP v4 and v6, `localhost`, single label, port, `xn--`); duplicate, no card, several cards; the copy's secret equals the master's and its label carries last4; delete refuses the master and non-payment items; update re-copies only stale shops; deny route `not_pending`; `/status` gate; push payloads with previews on and off; 401 without login through `hermes_driver`.
- **Crew unit (`CrewTests`):** command parsing (labels with quotes and `·`, missing last4, `xn--`); receipt rows and the offer from each fixture result; `WaitingKind.payment`; `PushRoute` for both kinds; card state for detail 200, 404 after retries, network error, and no `payments` feature.
- **Scenarios** (recorded with `Tests/chat_probe/run.sh record`, on `crew-test` with its test shop, after PR A is deployed): `payment-approve`, `payment-deny`, `payment-expire` (waits out the 300 s), `payment-no-shop` (a throwaway `crew-test-*` bot with no shops), `payment-iframe`. Each asserts the chat rows, the bot row status during and after, and the crew-push pushes, as `BotMentionScenarioTests` does. The probe answers with `approval.respond`; the hold itself is covered by UI tests.
- **UI tests (iOS Simulator, fixtures):** the card shows host, total, claim line; a tap opens the dialog and Cancel leaves the card; `press(forDuration: 1.2)` approves and the fixture records `approval.respond` with `once`; a 0.6 s press springs back and sends nothing; Deny; the ended-request notice; Add Shop validation errors and success; the offer opens the sheet with the host filled in.
- **Renders** (iPhone, light and dark; Mac via `snapshot.sh` where it renders): card loaded, mid-hold, approved, details loading, couldn't load, `xn--`, countdown; offer card; receipt rows; Shops with shops, empty, no card, several cards, old card, `local` footer; Add Shop sheet; Show All.
- **Test pages** (`pages/`, live after the next `v*` tag):
  - `checkout-test.html`: autocomplete card fields (`cc-number`, `cc-exp-month`, `cc-exp-year`, `cc-csc`, `cc-name`, `postal-code`), "Total 499 kr", a "Save card" checkbox, a Pay button that shows "Paid with card ending 4242". No network calls.
  - `checkout-iframe-test.html`: the same total with the card fields inside an `<iframe srcdoc>`, to record the "card fields not found" path.
- **Device checks** (`./device.sh` and the rebuilt Mac app): lock-screen push and its Deny, the hold's haptics, a cold launch from the push, the push withdrawn after answering on the Mac.

## Not in scope

- Approve from a notification, Face ID, Touch ID, passcode.
- Iframe checkouts, one card for any shop without adding it, several master cards.
- Reading the real charge or order back from the shop.
- Payments in group rooms or other sessions.
- Detecting by `surface` (plan step 6, after upstream).
