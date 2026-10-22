# Payments: approve every purchase

A bot shops in a real browser on the server. When it reaches a checkout, it asks to fill the card. Crew shows a payment card in the bot's chat and as a time-sensitive notification, and nothing is filled until the user holds **Hold to Pay**. This spec covers the experience on iPhone and Mac; the crew-push/Crew API is in [payments-contract.md](payments-contract.md). Research, threat model and server steps: [docs/payments.md](../payments.md) (issue #9). Where they differ, these two files win.

Researched against Hermes **0.22.1**.

## Settled constraints

- One **master card** in crew-push's own vault (`<root>/vault/crew-push/`, since 0.6.0; before that the default profile's vault), without an origin. Each shop is a copy bound to one exact `https` origin in the bot's own vault, made by a crew-push route. Neither Crew nor the bot sees the number; only the last four digits leave the server, in the copy's label (as on every receipt).
- crew-push requires `amount`, `merchant` and `reason` on every payment fill. They are the bot's claim and are shown as such. The real cap is a low-limit virtual card.
- Payments run only in the bot's **Bot Chat** until upstream Hermes stops other clients and typed replies from resolving payment approvals ([plan step 5](../payments.md#5-upstream-hermes-pr-and-issue-s)).
- A payment is detected by the command prefix `Fill payment card '` and verified with crew-push by `request_id`; by `surface` once Hermes sends it.
- **No Face ID, Touch ID or LocalAuthentication.** The deliberate act is a press and hold inside Crew. No approve action outside the app.
- **Server side is crew-push only:** hooks, dashboard routes and JSON files in `plugin-data/crew-push/` next to `devices.json`.
- Shopify's checkout (card fields in frames from `checkout.pci.shopifyinc.com`, the common case for Swedish shops) is supported from crew-push 0.6.3: the user approves as usual, the push ends with "Card fields by Shopify", and crew-push fills the frames after the approval. Other iframe checkouts (Stripe Elements, Klarna, Adyen) are unsupported: crew-push blocks the fill before any approval (`crew_no_shop_card`, naming the payment frame's origin), so the user is never asked, and the bot says so. A checkout that moved to Shop Pay (`shop.app`, only with a Shop Pay session) is blocked the same way.
- The `local` terminal backend risk is accepted for now and stated in [Security](#security) and in the inspector.

## The moment

Scout is buying winter boots. A card slides up above the composer: a small card art, **Pay www.zalando.se**, *Zalando · Winter boots, size 43* and a large **499 kr**, with "Scout states the amount and the shop." The user presses and holds **Hold to Pay**; a fill sweeps across the capsule for one second with a soft haptic at the start; a checkmark draws itself, a success haptic fires, and the card folds into a one-line receipt in the transcript: "Approved 499 kr at www.zalando.se". Scout clicks the shop's own Pay button and replies with the order number. On a locked iPhone the request arrives as a time-sensitive notification from Scout, "Pay at www.zalando.se?", whose tap opens straight to the card.

## Setup

### The master card

- Added or replaced from the Shops card with **Add Card…** / **Replace Card…** (crew-push 0.5.0 stores it with `VaultStore.add_item`, kind payment, no origin; `hermes vault add` cannot, since 0.22.1 requires an origin for payment items). The number passes through Crew once and is never kept there: [master-card.md](master-card.md).
- Every bot's **Shops** card starts with a card row:
  - **One card:** a small card art (rounded rect, 40 × 26 pt, a fixed graphite gradient with a 1 pt hairline so it reads in light and dark) and "Shopping card •••• 4242".
  - **No card:** "No card on the server", footer "Add the card Crew copies to each shop you add. Bots never see the number.", and **Add Card…** ([master-card.md](master-card.md)). Add Shop is disabled.
  - **Several cards without a website:** "More than one card on the server", footer "Keep one card without a website; Crew can't tell which to use." Add Shop is disabled.
- When the master is replaced, each existing shop row shows "Old card" in orange (its copy no longer matches). **Update Shops** re-copies the current card into them ([master-card.md](master-card.md)). A payment item someone added by hand with another card also reads "Old card"; that is fine.
- With crew-push 0.5.0 the default profile's own Shops card adds "Kept here, never used to pay."; from 0.6.0 the card row reads "Card used for new shops" instead ([inspector-passwords.md](inspector-passwords.md)). The master never appears as a shop.

### Shops (inspector, Passwords tab)

A **Shops** card in the Passwords tab after Logins and 1Password (in Info before #58), on iPhone (profile page) and Mac (inspector column), using the existing `Card` (PR B extends it to take several footers and a tinted one).

- **Rows:** the host in body text and "Added 12 Oct" or "Last paid 14 Oct" in secondary. A host with an `xn--` label gets an orange `exclamationmark.triangle.fill` and "Unusual address: check the spelling".
- **Empty:** "Scout can't pay anywhere yet." A bot can pay exactly when it has a shop; there is no separate switch.
- **Add Shop…** (`plus.circle`) opens the sheet below.
- **Remove:** swipe to delete on iPhone, context menu Delete and the Delete key on Mac. No alert: it is undone by adding the host again. The row leaves when the route answers; on failure it stays and an inline error shows.
- **Footers**, each only when true:
  - "Scout pays only on these sites, and asks you every time." (when there is a shop)
  - Browser toolset off: "Turn on Browser in Capabilities so Scout can shop."
  - `terminal.backend` is `local`: "Bots on this server run commands next to the card, so a misbehaving bot could read it. Keep the card's limit low."
  - Dashboard login off (`gate: false`): "Payments are off: this server has no dashboard login." in red.
- Offline: the last list stays; Add and Remove are disabled. Loading: a small `ProgressView`, as other cards do.

### Add Shop sheet

- iPhone: `.medium` sheet with a grabber; Mac: window sheet 360 pt wide. Title "Add Shop", **Cancel** leading, **Add** trailing, disabled until the field parses.
- One field, "Website", placeholder `www.zalando.se`, URL keyboard, no autocorrect or capitalisation. A pasted checkout URL works.
- Under it, the host is the largest text: "The card will fill only on **https://www.zalando.se**." A non-ASCII host is shown in its punycode form, which is what the browser reports, and the line turns orange: "This address uses special characters and could imitate another site."
- Hint: "Use the address shown at checkout; www.zalando.se and zalando.se are different sites. Only add sites you'd shop at yourself."
- The server validates; its error codes show inline in red under the field.
- After Add the sheet closes and the new row highlights briefly.

## The shopping turn

1. The work log shows browsing as today. `browser_vault` gets a style: icon `creditcard`, verb "Checked cards" for `list`, "Card" for `fill` with the subject "at www.zalando.se". The expanded row shows `amount`, `merchant`, `reason` and the result like any tool.
2. While the approval is pending, the composer bar holds the **payment card** in the approval card's place (560 pt max, 16 pt sides, the locked values). If a payment and another approval are pending in the same chat, the payment shows first (it has the clock), the other after it.
3. After the decision the turn shows a **receipt row**: a centred secondary line with a leading `creditcard` symbol, outside the collapsed work log:
   - "Approved 499 kr at www.zalando.se" (green check)
   - "Denied 499 kr at www.zalando.se" (red)
   - "Payment request expired"
   - "Payment request cancelled"
   - "Approved, but the card wasn't filled: <short reason>" (orange)
   - "Payment not approved" when only Hermes' generic result is there
   It is derived from the `browser_vault` fill call and its result: from `crew_payment` when crew-push decorated it, else from the raw result (`error_type: payment_declined` gives "Payment not approved"; `success` with `fields` lacking `cc-number` gives "not filled"). It survives reloads and history paging with no extra request.
4. **Bot list:** status "Wants to pay" (`WaitingKind.payment`, decided from the open request's command prefix, no network call) in the style of "Needs approval". Preview, time and unread are unchanged; the bot's reply after the purchase updates them as any reply does.

## The payment card

### Layout

Inside the existing glass card shape (`.glassEffect(in: .rect(cornerRadius: 28))`, 16 pt padding):

- **Header:** the bot's 20 pt avatar and "Scout wants to pay" (subheadline semibold). Trailing, only in the last 60 s: "0:45" in monospaced digits, orange under 15 s, counted from the server's `now` so device clock skew does not matter.
- **Merchant line:** "Pay" (title3, secondary) and the host (title2 semibold), wrapping by character if it must, never truncated. The host comes from the approval's `command` (the vault item's bound origin), the one fact Hermes enforces. An `xn--` host gets the orange warning line.
- **Details,** label/value rows like the Apple Pay sheet (labels caption uppercase secondary):
  - CARD: the card art (24 × 16 pt) and "Shopping card •••• 4242"
  - FOR: "Zalando · Winter boots, size 43" (up to 3 lines)
  - hairline
  - TOTAL: "499 kr" (title2 semibold, trailing)
  At large Dynamic Type sizes labels stack above values.
- **Always on screen** (#91): the header, the "Pay <host>" line (wrapping), the TOTAL row and the buttons. In iPhone landscape the header, host and claim sit beside the details with the buttons full width below. When space is short (landscape, short Mac window, largest text) only CARD and FOR scroll and the claim line shrinks away; the button is always **Hold to Pay**, never a "Pay…" fallback.
- **Claim line** (footnote secondary, always shown): "Scout states the amount and the shop. The card fills only on www.zalando.se."
- **Buttons:** **Deny** (glass, destructive) leading, **Hold to Pay** (glass prominent) trailing, flexible width, capsule, as Allow Once/Deny today.

### Which card shows

The details come from crew-push by `request_id`. Crew shows the payment card with **Hold to Pay** only when crew-push returns an entry whose origin and card label equal what Crew parsed from the command. Otherwise:

- **Loading** (one retry, normally well under 200 ms): redacted placeholders, Hold to Pay disabled.
- **Network error:** "Couldn't load the amount." with **Try Again**; Hold to Pay disabled, Deny works.
- **Not verified** (crew-push says `unknown_request`, the entry does not match the command, or crew-push has no `payments` feature): a payment-shaped card with **Deny only** and "Crew can't verify this payment request." plus "Update crew-push to pay from Crew." when the feature is missing. A real fill that crew-push missed fails safe; an MCP server mimicking the text gets nowhere.

### Hold to Pay

The hold guards against a stray tap in the bar where the user types. It is **not** a security boundary ([Security](#security)).

- **Press:** the capsule scales to 0.97 and a lighter fill sweeps leading to trailing over **1.0 s**; a light impact haptic on touch down (iOS).
- **Release early:** the fill springs back in 0.25 s. Nothing is sent.
- **Complete:** a `.success` haptic; the label becomes a `checkmark` drawn with `.symbolEffect(.drawOn)` and "Approved". Crew sends `approval.respond` with `once` and the `request_id`. After 0.8 s the card collapses (`.smooth`) and the receipt row arrives with the result.
- **Tap** (under 0.3 s), **Space or Return** with keyboard focus, **VoiceOver, Voice Control and Switch Control** activation: a confirmation dialog on the button, "Pay 499 kr at www.zalando.se?" with **Pay** and **Cancel**. Everyone has a path, and no single tap approves.
- The card's buttons have no keyboard shortcut, so Return in the composer never reaches them. The card never takes focus. On iPhone, the card arriving, a tap on it or a downward swipe on it dismisses the keyboard (the draft stays) so the card has room; swiping never dismisses the card, which leaves only through Deny, Pay or expiry (#91).
- **Answer fails:** the card returns with an inline line: "Couldn't reach Hermes. Try again." (socket) or, for `resolved: 0`, Crew fetches the request's state and collapses to the matching receipt line.
- **Reduce Motion:** no scale or spring; linear fill; the check appears without drawing.
- **Mac:** the same with a mouse or trackpad press, no haptics.

### Deny

A plain tap, no confirmation: denying is safe. The card collapses; the row reads "Denied …". crew-push tells the bot 'The user denied this payment. Do not retry in this turn; ask what they want instead. This cancelled only this attempt. "Never retry payment_declined" means never retry on your own; if the user later asks you to pay again, call browser_vault fill again and Crew will ask them to approve it.' On the user's next message, crew-push adds a one-turn note that retrying is allowed now.

### Expiry

Hermes waits `approvals.timeout` (default 300 s) and declines. The countdown shows in the last 60 s; at zero the card collapses, the row reads "Payment request expired", and the bot is told not to retry in this turn, only when the user asks again in a new message (this cancelled only this attempt; Crew asks the user to approve a new fill).

## Push

- **Kind `payment`**, category **`CREW_PAYMENT`** (options `.hiddenPreviewsShowTitle` like every Crew category, `hiddenPreviewsBodyPlaceholder` "Payment request"), time-sensitive, expiring with the request, thread `profile.<bot>`, no badge (as for the other kinds).
- **Content:** title the bot's name (Crew's rule for every push), subtitle "Pay at www.zalando.se?", body "499 kr · Zalando · Winter boots, size 43". A locked phone with previews "When Unlocked" shows "Scout / Payment request". With crew-push's `previews` off: subtitle omitted, body "Wants to pay".
- **Tap:** opens that bot's chat with the card (cold launch included; it arrives with `session.resume`'s `open_requests`).
- **Actions: Deny only** (`.destructive`, symbol `xmark`; no `.authenticationRequired`, no `.foreground`). Decided:
  - **No Approve action.** Without authentication anyone holding the phone could pay, and an Apple Watch double tap selects the first non-destructive action. Paying happens only in the app.
  - **Deny** fails safe and saves a trip into the app, so it stays. The handler is push.md's action transport (5.6): fresh `ws-ticket`, connect, `client.capabilities`, `approval.respond {session_id, choice: "deny", request_id}`, disconnect. It refuses to act without a `request_id`. On failure a local notification: "Couldn't reach Hermes. Open Crew to answer."
- **Cleanup:** crew-push sends a background `payment_resolved` to every device when the request ends, and Crew removes the matching notification. Background pushes can be throttled or miss a force-quit app, so Crew also removes delivered `payment` notifications on activation and after each `session.resume` when `expires_at` has passed or the request is not open.
- **Foreground:** no banner while that bot's chat is on screen; a banner on any other chat.
- **Push off** (local notifications): a payment raises "Wants to pay" with category `CREW_APPROVAL` (no actions), since there is no `request_id` to deny.

## Results

| Case | Server signal | Crew shows | Bot |
|---|---|---|---|
| Filled | `success: true`, `cc-number` in `fields` | row "Approved 499 kr at …" | clicks the shop's Pay, reports the outcome; told never to tick "save card" |
| Denied | `payment_declined`, state `denied` | row "Denied …" | does not retry in this turn; fills blocked until the user's next message, which carries a one-turn note that retrying is allowed, so it calls `fill` again if asked |
| Expired | `payment_declined`, state `expired` | row "Payment request expired" | says so; same block |
| Cancelled | state `cancelled` (Stop, session closed) | row "Payment request cancelled" | nothing more |
| Page left the shop after approval | `origin_mismatch`, `origin_changed` | row "Approved, but the card wasn't filled: the page left www.zalando.se" | may go back and ask again (a new card) |
| Card fields not found | "No payment form fields…", or success without `cc-number` | row "… wasn't filled: card fields not found" | says the checkout probably uses a payment frame Crew can't fill (iframe) |
| You took over the browser | `human_has_control` | row "… wasn't filled: you're controlling the browser" | waits |
| Other fill failure | `eval_failed`, `supervisor_required`, other errors | row "… wasn't filled: the browser didn't respond" | explains briefly |
| No card for this shop | `list` decoration or the fill block with `missing_shop` | **offer card** (below), no payment card, also after the reload | "I need www.zalando.de added as a shop in Crew." |
| Card fields in a payment frame other than Shopify's (Stripe, Adyen), or the checkout moved to Shop Pay (`shop.app`) | block `crew_no_shop_card` without `missing_shop`, before any approval | a failed tool row, no payment card | tells the user Crew can't fill this checkout and that nothing was asked, charged or ordered, and offers to send the cart link so they finish on their own device (the checkout tab is in the bot's browser, which the user can't see; crew-push 0.6.6) |
| Shop page not open (the bot read the checkout with `web_extract`, or the browser sits on `chrome://new-tab-page`) | block `crew_no_shop_page`, before any approval | a failed tool row | opens the checkout with `browser_exec` (Browser Use, the default) or `browser_navigate` (built-in browser), then calls `fill` again |
| Details missing | block `crew_missing_details` | a failed tool row | retries with the three args |
| Outside Bot Chat (group room, other session, `execute_code`) | block `crew_not_bot_chat` | the bot's explanation | "I can only pay from my chat in Crew." |
| Another identical request pending | block `crew_one_at_a_time` | nothing new | waits for the first answer |
| Dashboard login off | block `crew_gate_off` | the bot's explanation; red Shops footer | "Payments are off on this server." |
| crew-push or network error | 5xx, timeouts | card: "Couldn't load the amount." + Try Again | |

### No card for this shop

crew-push reads the page the way Hermes' `browser_vault` does, through the per-task CDP supervisor that `browser_exec` (Browser Use mode) or a built-in browser session attaches, and never starts a browser itself. A fill with no page on the shop's origin is blocked before any approval, with a message that names the navigation tool the bot has; a browser it cannot read blocks the same way, since Hermes' fill needs that supervisor too.

crew-push raises `missing_shop` with the page's own origin in two places: a `list` call while the current page has card fields (Hermes' payment field probe), and a payment `fill` blocked before any approval because no open tab is on the item's origin while the current page has card fields. The user never approves a fill that cannot happen.

When the latest turn is finished and its last `browser_vault` result carries `missing_shop` (crew-push sets it only for an origin with no shop in this bot's vault; Crew keeps no shop list of its own), the composer bar shows an **offer card**:

- "Scout needs a card for **www.zalando.de**", with the `xn--` warning when it applies, and "Only add sites you'd shop at yourself."
- **Not Now** dismisses it for this turn. **Add Shop…** opens the sheet with the host filled in; the user still taps Add. With no usable master card the button is replaced by "Add a card on the server first."
- Only after the user's Add, Crew sends a hidden prompt (`display_kind: "hidden"`): "I added https://www.zalando.de to your shops. Continue the purchase." The transcript shows a centred secondary line "Added www.zalando.de to Shops", and the normal payment card follows.

#### The offer stays (fix for 2026-10-18)

A bot listed its cards at a checkout with no shop, crew-push answered with `missing_shop` (twice), the offer flashed when the turn ended and vanished, and the bot asked the user to "add the payment setup in Crew" in text instead. crew-push was right; Crew lost the offer when it reloaded the turn from history. Hermes 0.22.x stores a turn differently from what it streams:

- **The `tool_call` bridge.** With deferred tools the model calls `tool_call {"calls": [{"name": "browser_vault", "arguments": {"action": "list"}}]}`. Live `tool.start` events carry the underlying name (`browser_vault`) and arguments; the stored assistant row keeps `tool_call`.
- **The untrusted envelope.** Stored results of `browser_*`, `web_*` and `mcp_*` tools (32 characters or more) are wrapped as `<untrusted_tool_result source="browser_vault">`, a fixed notice line, a blank line, the result, and `</untrusted_tool_result>`. Live `tool.complete` carries the bare result.

After `message.complete` Crew replaces the live turn with the stored one (`sync`), so the offer's lookup (`browser_vault` by name, result as JSON) found nothing. The same broke receipt rows and the `browser_vault` work-log style after any reload, although this spec says they survive reloads.

Crew now reads history the way the turn streamed:

- An assistant call named `tool_call` whose arguments hold exactly one entry (`{"calls": [{"name", "arguments"}]}` or the flat `{"name", "arguments"}`) becomes that entry's tool: its name, and its arguments as a JSON string (an object is re-serialised, a string kept as is). The call keeps the bridge's id, which is the stored tool row's `tool_call_id`, and that row holds the single entry's own result, not a list (the recorded rows show both). Batches and arguments that don't parse stay as `tool_call`, as Hermes itself treats them.
- A tool result shows without the envelope only when it starts with `<untrusted_tool_result source="<name>">` where `<name>` is the call's resolved name and starts with `browser_`, `web_` or `mcp_`, and ends with `</untrusted_tool_result>` (one newline before it is dropped). Crew then keeps what follows the first blank line. Anything else is left as stored. The expanded work-log row shows the result as it did live, and `toolStatus` reads failures from it (a wrapped `crew_no_shop_page` block showed as a success before).
- This applies to every deferred tool, not only `browser_vault`: a bridged `web_search` or `browser_exec` row in history now has its own name, icon, verb and subject in the work log, as it had live, instead of "tool_call". No row is removed; nothing else reads the name.
- Hold to Pay is unaffected: the payment card comes only from a live `approval` request and crew-push's `request_id` lookup, never from history rows, so this cannot create or revive a payment card. Offers and receipts read only results whose resolved name is `browser_vault`; page text inside a result cannot set their keys.

The offer then follows the history, and no new state is stored:

| Moment | Offer |
|---|---|
| Turn streaming | hidden (as before) |
| Turn ends | shows, and stays through the history reload |
| Chat reopened, app relaunched, cold launch from the reply push | shows (derived from the loaded rows) |
| The other device (iPhone and Mac) | shows (same rows) |
| **Not Now** | hidden for that turn in every window of this bot on this device until the app relaunches (kept on the bot's `ChatSession`, by turn id, which the reload keeps); the other device still shows it |
| **Add** in the sheet | the hidden "I added …" prompt starts a new turn, so the offer leaves on every device and "Added … to Shops" shows |
| The user sends a new message | leaves with the old turn; the bot's next `browser_vault` result decides again |
| Shop added in the Passwords tab, or on the other device, before tapping Add | stays (Crew keeps no shop list); Add in the offer's sheet treats crew-push's `duplicate_shop` as done: the sheet closes and the same hidden (with the offer's own origin) "I added … Continue the purchase." prompt goes to the bot, since the shop is there. The Passwords tab's own sheet still shows "… is already a shop." |
| Offline | shows from the loaded transcript with the composer's offline line; the sheet's Add is disabled until connected (as today) |
| Add fails | the sheet keeps the field and shows the contract's inline error; nothing is sent to the bot |
| Server without the `payments` feature | hidden (as before) |

Other surfaces are unchanged and stated here so the fix is checked against them: the bot row shows the bot's reply as preview, time and unread like any reply, and no "Wants to pay" (nothing is pending); the reply push is the normal `reply` push with the bot's text; the offer card is the existing `ShopOfferCard` in light and dark on iPhone and Mac, with the host wrapping, never truncated.

#### What the bot is told (crew-push 0.6.1)

In Bot Chat, the `missing_shop` hint on `list` and the `crew_no_shop_card` message (raised only in Bot Chat) both read: "There is no card for https://www.zalando.de. When your turn ends, Crew shows the user an Add Shop button for this site; only the user can add it. Stop before choosing a payment method or placing the order, don't pay another way, and don't call browser_vault again in this turn. Say in one line that this shop needs adding in Crew, then end your turn. Don't ask the user to set up cards or payments by hand, or to confirm the price just for paying: Crew asks them to approve the amount when you fill the card. When they add it, Crew tells you to continue." Outside Bot Chat (no offer shows there) the `list` hint keeps the old "Tell the user they can add this shop in Crew, then wait." Both stay under Hermes' 2048-character cap. Dropping the separate price question is a behaviour change: the payment card shows the amount and the hold approves it. The bot still cannot add a shop: no tool or route does it, and the hidden "I added …" prompt only follows the user's Add.

## iPhone and Mac

- **iPhone:** card in the chat's composer bar; Shops on the profile page; Add Shop as a medium sheet; lock screen and Notification Center with Deny; haptics.
- **iPad:** as iPhone; 560 pt max card; form sheet.
- **Mac:** card in the chat column; Shops in the inspector column; Add Shop as a window sheet; banner and Notification Center with Deny in the banner's options; no haptics. A bot whose chat is not selected shows "Wants to pay" in the list and its banner's click selects it.
- **Both, light and dark:** system materials and secondary styles; the card art has a fixed gradient with its own hairline.

## Other states

- **Offline:** the card stays with its details; Hold to Pay and Deny are disabled with the composer's offline line (the existing 2 s delay). The server expires the request on its own; on reconnect `session.resume` removes the card if it is gone.
- **Cold launch from the push after the request ended:** a notice in the card's place: "This payment request expired at 14:07." (or "was approved" / "was denied" "on another device"), with **OK**. Never a silent empty chat.
- **Several bots at once:** each chat has its own card, each bot row says "Wants to pay", each push is its own notification. Within one chat crew-push allows one pending payment, so cards never stack.
- **Answered elsewhere** (the other Crew device, TUI, Desktop): Hermes sends `request.cancel` only when the other client used `approval.respond` (Crew does); TUI and Desktop answer with a response frame, which sends nothing. So Crew also removes the card when the fill's `tool.complete` arrives or the turn ends. Either way the receipt row follows.
- **Stop while the card is up:** Hermes cancels the request; the card leaves; row "Payment request cancelled".
- **Bot deleted or session closed while pending:** `approval.cancelled`; the card leaves.
- **Long content:** host never truncated; merchant and reason clamp to 3 lines (the expanded work-log row has the full text); amount is capped at 32 characters server side.
- **Group rooms:** fills are blocked outside Bot Chat, so a room only shows the bot's explanation. A payment-looking request that still reaches a room cannot be verified and gets the Deny-only card.

## History

The receipt rows in the bot's chat are the history: payments only run in Bot Chat, so that chat is the per-bot log, in context, with the bot's own words around each payment. Shop rows show "Last paid". crew-push's `payments.json` keeps the last 200 requests server side for request lookup and for comparing the bot's stated amounts with the bank statement. The shop's confirmation and the statement are the receipts; Crew stores nothing.

## Accessibility

- The card is one container: header, merchant, details, claim, buttons. Its label: "Payment request from Scout. Pay at www.zalando.se. Zalando, Winter boots, size 43. Card ending 4242. Total 499 kr, as stated by Scout." (the amount string as the bot gave it).
- **Hold to Pay:** label "Hold to Pay", hint "Double-tap to confirm the payment." VoiceOver activation and the custom action "Pay" open the confirmation dialog. Deny: "Deny payment".
- The countdown is announced at 60 s and 15 s (`AccessibilityNotification.Announcement`), never every second.
- The `xn--` warning is part of the host's label.
- Receipt rows read as their text.
- Dynamic Type throughout, capped at accessibility size 3 on the payment card so its pinned parts fit; 44 pt targets on iPhone; every state has a symbol and words, never colour alone.
- Full Keyboard Access and the Mac keyboard reach both buttons by Tab; Space or Return on Hold to Pay opens the dialog.
- Reduce Motion as above; Reduce Transparency uses the system's opaque glass.

## Security

| Threat | Handling |
|---|---|
| **Approval spoofing** (an MCP elicitation or tool sending `Fill payment card '…' on …`) | Hold to Pay appears only for a request crew-push recorded from its own `pre_tool_call` on a real `browser_vault` fill, with origin and label matching the command. Anything else gets the Deny-only card. |
| **Coalescing hijack** (an identical pending MCP elicitation becomes the leader and the real fill a follower, so the user's hold answers the attacker's request) | crew-push blocks a payment fill while any approval with the same command is pending in the session, ignores `pre_approval_request` with `coalesced=True`, and binds a `request_id` only to an entry that appeared after the fill's `pre_tool_call` and matches its command, exactly once; otherwise it records nothing and Crew shows Deny-only. |
| **The bot approving its own payment** | A bot cannot reach Crew. On a dashboard **without** the login gate, `GET /` hands any local process the session token, which also opens `/api/ws` and `approval.respond`; crew-push therefore blocks every payment fill unless the dashboard has reported its login gate on (persisted in `gate.json`; fail closed until seen). Under the `local` backend a bot can still read the server's files and defeat this and the vault alike: the accepted risk below. |
| **Replayed approval** | Crew answers with `approval.respond {request_id}`, a one-time `uuid4().hex`; a second answer returns `resolved: 0` and changes nothing. There is no approve route and no approve push action. Pushes carry ids, never capabilities. |
| **Look-alike host** | The page origin is as bot-controlled as its text (the bot chooses where to browse), so the offer is a bot-initiated "add this site" and gets the same caution: https only, exact origin, IDNA-encoded and `xn--` flagged everywhere the host shows, "Only add sites you'd shop at yourself", a deliberate Add in a sheet where the host is largest, and the host shown again on every payment. Typo and subdomain look-alikes (`zalando.se.pay-checkout.com`) are not detected; the user reads the host. |
| **Amount differs from the charge** | Not preventable: Hermes approves the fill, not the cart. The card labels the amount as the bot's claim every time, `payments.json` keeps it for the statement, and the issuer's low limit is the cap. |
| **Display spoofing** in amount, merchant, reason | crew-push strips Unicode Cc and Cf (bidi overrides, zero-width), collapses whitespace, caps lengths (32/64/140) and requires a digit in `amount`. Crew renders plain `Text`, no Markdown or links. |
| **Nagging** | One pending payment per session. A deny or expiry blocks fills for the rest of that turn only: the block lifts when the user sends a new message in that session, so "try again" works. Agent messages, delivery notices and bracketed system turns do not lift it, so another bot cannot talk it open. Crew's hidden prompts (an A2UI action answer, the "Continue the purchase" prompt after Add Shop) do lift it, since each is sent only after the user's own tap. |
| **Other clients** | Until upstream lands, another client attached to the same Bot Chat (TUI, Desktop) can answer with `session`, `always` or `all: true`; Hermes treats each as one fill, but `all` resolves every pending approval in the session. Payments run only in Bot Chat, which messaging platforms do not drive, so typed replies there cannot pay. |
| **Fail-open hooks** | The payment branch of `pre_tool_call` is not under crew-push's `quiet` wrapper: it catches its own exceptions and returns a block. `transform_tool_result` is fail-open in Hermes, so Crew derives the receipt from the raw result too. |
| **Wrong tab** | Hermes may fill any open tab on the bound origin; same origin, same shop. Accepted. |
| **Card read back, saved cards, iframes** | As in [the plan](../payments.md#threat-model). Iframes other than Shopify's and partial fills without `cc-number` count as not filled. A Shopify frame fill that stops part way is not filled either and tells the bot some fields may hold card details, so the user finishes by hand. |
| **The `local` backend** | Every bot's shell runs next to every `vault.key`, so a misled bot could decrypt the card or forge past the gate. Accepted now and shown in the inspector; the cure is the `docker` backend for every bot. Worst case is one month of the card's limit. |
| **Lock screen** | The bot name always; host, amount, merchant and reason only with previews; never card data beyond the last four. |

## Build: two parallel PRs

The contract fixtures (`Tests/fixtures/payments/`, listed in the contract) land first in PR A's first commit and are copied unchanged into PR B, so B builds against them without waiting.

**PR A, crew-push 0.4.0** (`server/crew-push`, `pages/`): `crew_push/payments.py` (log, claim cleaning, site normalisation, shop copy), the payment branches in `crew_push/hooks.py` (`pre_tool_call`, `pre_approval_request`, `post_approval_response`, `transform_tool_result`, the reset in `pre_llm_call`, kinds `payment` and `payment_resolved`), routes and `/status` fields in `dashboard/plugin_api.py`, version files and `provides_hooks`, the two test pages, a line per kind and route in `docs/push.md`.

**PR B, Crew** (`Sources`, `Tests`): `ApprovalParams.requestID` and `PaymentRequest` parsing, `PaymentCard`, the hold control and dialog, `OfferCard` (`Sources/Chat/RequestCards.swift`); detail fetch, `approval.respond` for payments, card removal on `tool.complete`, the ended-request notice, the hidden prompt after Add (`ChatSession.swift`); payment-first ordering (`ChatView.swift`); the `browser_vault` style and receipt rows (`WorkLog.swift`, `Transcript.swift`); `WaitingKind.payment` and "Wants to pay" (`BotStore.swift`, `BotsView.swift`); `CREW_PAYMENT`, `payment_resolved`, cleanup on activation, `PushRoute.requestID` (`Sources/Push`); the Deny action's handler, which is push.md 5.6's background action transport (ticket, connect, capabilities, respond) and is not built yet (if it proves heavy, the cut is a tap-only payment push with no actions); an unconditional `GET /status` on every authenticated connect, independent of notification permission, so crew-push learns the login gate (today `PushCenter` only calls crew-push when notifications are authorized); Shops card and sheet (`Sources/Inspector/Shops.swift`, `BotInspector.swift`, `Card` footers); snapshots; `docs/PLAN.md` Decisions lines (hold to pay, payment card, Shops).

## Tests

- **Contract fixtures:** crew-push asserts its output equals them; Crew decodes every one.
- **crew-push (pytest):** each block code in order and the allow path; an exception in the payment branch blocks; an identical pending MCP elicitation blocks the fill; `coalesced=True` is ignored; binding with another approval pending in the session; a fill from `execute_code` (no `session_id`) is blocked; a second fill in the declining turn stays blocked, a delivery or agent turn does not clear `after_decline`, and a user turn or a hidden Crew prompt does; the denied and expired texts say the decline cancelled only that attempt; the retry note rides only the first user turn after a decline (not agent, delivery or system-note turns) and is gone after a new fill attempt; every block message stays under Hermes' 2048-character cap; claim cleaning (bidi, zero-width, caps, digit rule); log state per `choice`; `transform_tool_result` per outcome including a success without `cc-number`; `missing_shop` from `list` with and without card fields, and not when another tab is on the bound origin; `crew_no_shop_page` under Browser Use (no supervisor, `chrome://new-tab-page`, no page; never starts a browser) and in the built-in mode (before and after `browser_navigate`), naming `browser_exec` or `browser_navigate`; any of the item's `allowed_origins` counts; an unreadable browser blocks; site normalisation table (path, query, case, `http`, IPv4, IPv6, `localhost`, single label, port, Unicode to punycode, `xn--`); duplicate, no card, several cards; the copy's secret equals the master's and its label carries last4; delete refuses the master and non-payment items; `gate` read from `gate.json` in a fresh process; push payloads with previews on and off; 401 without login through `hermes_driver`.
- **Crew unit (`CrewTests`):** command parsing (quotes and `·` in labels, missing last4, `xn--`); verified, mismatched, unknown and feature-missing requests give the right card; the card leaves on `tool.complete` without `request.cancel`; receipt rows from decorated and raw results for every outcome; offer derivation; payment ordered before another approval; `WaitingKind.payment`; `PushRoute` for both kinds; stale notification cleanup.
- **Scenarios** (`Tests/chat_probe/run.sh record`, on `crew-test` with its test shop, after PR A is deployed): `payment-approve`, `payment-deny`, `payment-expire` (waits out 300 s), `payment-no-shop` (a throwaway `crew-test-*` bot without shops), `payment-iframe`, and `payment-two-clients` (a second socket answers once by response frame, once by `approval.respond`; Crew's card leaves both times). Each asserts chat rows, bot row status during and after, and crew-push's pushes, as `BotMentionScenarioTests` does. The probe answers with `approval.respond`; the hold is covered by UI tests.
- **UI tests (iOS Simulator, fixtures):** card shows host, total and claim line; a tap opens the dialog and Cancel leaves the card; `press(forDuration: 1.2)` approves and the fixture records `approval.respond` with `once`; a 0.6 s press springs back and sends nothing; Deny; the Deny-only card has no Hold to Pay; the ended-request notice; Add Shop errors and success; the offer opens the sheet filled in.
- **Renders** (iPhone light and dark, Mac light and dark via `snapshot.sh`): card loaded, mid-hold, approved, loading, couldn't load, Deny-only, `xn--`, countdown, large Dynamic Type, Reduce Motion approved; offer card; receipt rows; Shops with shops, empty, no card, several cards, old card, `local` footer; Add Shop sheet.
- **The offer stays:** a scenario replay of the real stopped turn's rows (sanitised, `Tests/fixtures/scenarios/shop-offer-history/`: the `tool_call` bridge and the untrusted envelope byte for byte, personal content, ids and the shop replaced) asserts the offer host, the work-log style and the bot row after the reload; unit tests for the bridge (object and string arguments, a batch stays) and the envelope (wrapped, no newline before the closing tag, a source that isn't the tool, a trusted tool, bare), and a receipt from a wrapped fill; unit tests that the offer leaves after the hidden-prompt turn, is hidden when a later `list` without `missing_shop` comes last, that the live events and the stored rows of the same turn give the same tool, result, offer and reply, that Not Now's turn id survives the reload, and `toolStatus` reads an error from a wrapped result; crew-push asserts the new hint on `list` (Bot Chat and elsewhere) and the block, including the stop-before-paying sentence; a UI test (`chat-payment-offer-history`, built through `Transcript(history:)`) shows the offer and opens Add Shop filled in.
- **Test pages** (`pages/`, live after the next `v*` tag): `checkout-test.html` with autocomplete card fields (`cc-number`, `cc-exp-month`, `cc-exp-year`, `cc-csc`, `cc-name`, `postal-code`), "Total 499 kr", a "Save card" checkbox and a Pay button that shows "Paid with card ending 4242", no network calls; `checkout-iframe-test.html` with the same card fields inside an `<iframe srcdoc>` for the not-filled path.
- **Device checks** (`./device.sh`, rebuilt Mac app): lock-screen push and Deny, the hold's haptics, a cold launch from the push, the notification removed after answering on the Mac.

## Not in scope

- Approve from a notification; Face ID, Touch ID, passcode.
- A payments history screen (the chat is the log).
- Iframe checkouts other than Shopify's, any-shop cards, several master cards.
- Showing "Card fields by Shopify" on Crew's payment card (crew-push sends `card_fields`; only the push shows it so far).
- Reading the real charge or order back from the shop.
- Payments in group rooms or other sessions; detecting by `surface` (plan step 6).
