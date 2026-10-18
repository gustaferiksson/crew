# Inspector Passwords tab: logins, 1Password and the card

Issue #58. Credentials leave the crowded Info tab for a fourth inspector tab, **Passwords** (after Info, Tasks, Routines). It holds three cards: **Logins** (the bot's own Hermes vault logins, added, edited and removed from Crew), **1Password** (one service account per bot, read only), and **Shops** (moved here unchanged except for the card row). The master card moves out of the default profile's vault into crew-push's own vault, so it belongs to no bot. Builds on [master-card.md](master-card.md) (#57, crew-push 0.5.0) and keeps parked #70 (the card moves to the device) a one-function change on the server and a card-row change in Crew.

These lines change with this spec: [payments.md](payments.md) "One master card in the default profile's vault", "The default profile's own Shops card adds 'Kept here, never used to pay.'" (now only against crew-push 0.5.0) and the "Shops (inspector, Info tab)" placement; [master-card.md](master-card.md) "inspector Info tab" and the first-card line about the default vault; [payments-contract.md](payments-contract.md) the master location and the `GET /payments` and `/status` shapes; [docs/payments.md](../payments.md) the `vault.list` and default-profile lines in "What Hermes already does", step 4's master location and the default-profile note, and the threat model (logins, the 1Password token, the new card location); `docs/PLAN.md` the inspector line (tabs), the Shops and Master card lines ("Info tab card", "launch profile's vault"), the iOS navigation line, and a new Decisions line; `server/crew-push/README.md` routes and version.

## Settled constraints

- **Logins use Hermes' own vault RPCs** over the dashboard WebSocket, each with `profile` (`@_profile_scoped` on the server; verified read-only on `crew-test`): `vault.list` (metadata only: `id`, `kind`, `label`, `origin`, `created_at`, and when present `identifier`, `identifier_type`, `has_otp`, `allowed_origins`, plus `backend`), `vault.sources` (`local`, `onepassword`, `bitwarden` with `installed`, `enabled`, `unlocked`), `vault.add {kind: "login", label, origin, secret: {identifier_type, identifier, password}}` (answers `{id}` only) and `vault.remove {id}` (`{removed}`). No crew-push route is needed for logins. Crew shows only `kind == "login"`; payment items stay in Shops, addresses are not shown.
- **Never show or fetch a password.** No call returns one. A password the user types crosses Crew and the WebSocket (WSS) once, inside one `vault.add`. Device rules as for the card ([master-card.md](master-card.md#settled-constraints)): plain `@State` in the sheet only, no `Codable` type holds it, the UI field is emptied the moment the request is built (the encoded frame lives only inside the pending call), the sheet's state dies on Cancel, no logs, no drafts, no pasteboard writes. Errors show fixed text: a `GatewayError.rpc` message is never shown. Crew sends a password or token only to an `https` server (WSS); with an `http` server the sheet says "Saving a password needs an https connection to Hermes." and Save stays disabled. The password is sent exactly as typed (not trimmed).
- **Honest copy.** A bot fills a login model-blind: the password never enters the chat, the model or Crew's transcript. It is **not** out of reach of a bot with a shell: under `terminal.backend: local` any bot on the server can read every `vault.key` and `.env` ([docs/payments.md](../payments.md#where-the-bots-shell-runs)). So the cards never say "never sees", and the same footnote as Shops shows when the bot's `terminal.backend` is `local` (read from `GET /api/config?profile=`, `local` when unset or unreadable).
- **Edit is add then remove.** Hermes has no update. Save adds the new login (same site, the new username and password), then removes the old one by id. A failure in between leaves two rows, never none. The item gets a new id, so a bot holding the old handle gets "no item" from `browser_vault` and lists again. `removed: false` means it was already gone.
- **Ambiguous writes reload.** After any failed Add, Edit or Remove (an RPC error, a timeout, a dropped socket, where the server may still have written), the card reloads `vault.list`. Two Hermes vault logins with the same origin and username are duplicates: each shows "Saved 18 Oct" (from `created_at`) so they can be told apart, and the older one can be removed from its menu.
- **Each login is bound to one exact origin.** The Website field uses the Shops rule (`shopHost(from:)`: https only, a public dotted name, IDNA lower-cased, a pasted URL works) and Crew sends `https://<host>`. Label is the host. `identifier_type` is inferred from the one "Username or Email" field: contains `@` → `email`, only digits, spaces, `+`, `-`, `(`, `)` with at least 7 digits → `phone`, otherwise `username`.
- **Only Hermes vault rows are editable.** Rows with `backend != "local"` are read only. Local rows with `has_otp` offer Remove but not Edit, since Crew cannot carry the stored verification-code key over and an edit would drop it.
- **1Password, one vault per bot.** Hermes reads 1Password through the `op` CLI with `OP_SERVICE_ACCOUNT_TOKEN` from the profile's own secrets (`<profile home>/.env`, re-read on every call). Crew connects by saving the token with `PUT /api/env {key: "OP_SERVICE_ACCOUNT_TOKEN", value, profile}` and disconnects with `DELETE /api/env {key, profile}`; it reads whether a token is saved from `GET /api/env?profile=` (`OP_SERVICE_ACCOUNT_TOKEN.is_set`, metadata only; Crew decodes nothing else). These REST calls refuse every redirect (a 3xx is "Couldn't reach Hermes."), as the crew-push card calls do. Crew never calls `vault.unlock`, `vault.source.set` or `/api/env/reveal`. Hermes does not report which 1Password vault an item comes from, so Crew does not invent it: rows say "1Password", and the connect steps suggest the vault name "Crew · <Bot title>" (a suggestion; renaming the bot later does not rename the vault).
- **No Connect on the default bot.** Saving an env value for the launch profile also publishes it into the dashboard process' own environment, which the token must never be in. The default bot's 1Password card shows its state but no Connect or Disconnect: "Set up 1Password for the main bot on the server."
- **Master card location:** crew-push 0.6.0 keeps the master in its own vault at `<Hermes root>/vault/crew-push/` (a `VaultStore` on that directory), not in the default profile's `vault.json.enc`, so no bot lists it in `browser_vault list`. It sits inside `<root>/vault/`, which Hermes' file tools refuse to read or write for every profile (`plugin-data/` has no such guard; Hermes notes the guard is not a boundary against a shell). `master_vault()` stays the single place that names it (for #70 phase 0, freezing or deleting it is one function). `/status` `features` adds `"card_vault"`.
- **One-time migration**, under the existing crew-push vault lock, before any master read or write: when crew-push's vault has no master and the default vault holds exactly one `payment` item without origin, crew-push adds that item (same label, same secret) to its own vault, then removes it from the default vault. When crew-push's vault already has a master and the default vault still holds exactly one origin-less card with the same secret (a move stopped half way), that leftover is removed. Any other combination is left alone, and `GET /payments` reports `legacy_cards` (the count of origin-less payment items still in the default vault, 0 normally). Shop copies stay in each bot's own vault.
- **Old crew-push (0.5.0, no `card_vault`):** Crew keeps today's card row, including the default bot's "Kept here, never used to pay.", since the card still lives there.

## Tab row

`InspectorTab` gains `.passwords`, title "Passwords", after Routines, on iPhone (pushed profile page) and Mac (inspector column). The selected tab keeps its glass capsule. Four capsules do not fit the Mac inspector near its locked 280 pt minimum or iPhone at large Dynamic Type, so the row is a `ViewThatFits`: the capsules with today's 12 pt side padding, then with 8 pt, and only then a horizontal `ScrollView` without indicators (`.scrollClipDisabled()` so the glass is not cut) that scrolls the selected tab into view. At the ideal 340 pt and on iPhone at default text size it looks as today. The inspector width is unchanged.

The Shops card leaves Info; Info keeps everything else in its order. The Passwords tab always shows (logins need no plugin); Shops shows in it only when crew-push lists `payments`, as before.

## Logins card

Title "Logins". Rows sorted by host, then username (as the Passwords app), each:

- Line 1: the host (body, one line, truncating in the middle). An `xn--` label gets the Shops warning, "Unusual address: check the spelling". A 1Password item with several websites (`allowed_origins`) reads "www.example.com +2"; an item whose origin is not `https` (an app link) shows its `label` instead.
- Line 2 (secondary, subheadline, one line, truncating at its end): the username or email, or "No username"; then " · 1Password" for 1Password rows, " · Verification codes" when `has_otp`, and " · Saved 18 Oct" on duplicates.
- Tapping a Hermes vault row without codes opens Edit Login. Context menu (long press on iPhone, right click on Mac) and VoiceOver actions: **Edit Login…** (`pencil`, not for codes rows) and **Remove Login…** (`trash`, destructive). 1Password rows have no menu and no tap action.
- **Remove** asks first, as Passwords does: a confirmation dialog "Remove the login for www.example.com?", message "Vera can no longer sign in there with it.", **Remove Login** (destructive) and Cancel. The row shows a small `ProgressView` while removing and leaves when `vault.remove` answers; on failure the list reloads and the row shows "Couldn't remove this login. Try again." in red.
- **Empty:** "Vera has no saved logins." in secondary.
- **Add Login…** (`plus.circle`, borderless) after a divider under the rows, as Add Shop.
- After Add or Edit the list reloads and the new row briefly highlights (the Shops tint).
- **Footers**, each only when true: "Vera fills these only on their sites, and the passwords never enter the chat." (when there is a row); Browser toolset off: "Turn on Browser in Capabilities so Vera can sign in."; `terminal.backend` `local`: "Bots on this server run commands next to the vault, so a misbehaving bot could read these passwords."
- **Loading:** small `ProgressView`. **Couldn't load** (`vault.list` failed): "Couldn't load logins." and **Try Again**; when 1Password is connected with a saved token the line reads "Couldn't load logins. 1Password may not accept Vera's token." (a bad token fails the whole `vault.list`, local rows included). **Offline:** the last list stays; Add, Edit, Remove and Try Again are disabled. The card reloads when the connection comes back.
- **Long content:** long hosts and usernames truncate on one line; many logins grow the card (the inspector scrolls).

## Login sheet

Same presentation as Add Card: iPhone `.large` sheet with a grabber, Mac window sheet 400 pt wide. Title "Add Login" or "Edit Login"; **Cancel** leading, **Add** or **Save** trailing (`ProgressView` while saving; Cancel disabled and no swipe-away while saving).

Grouped `Form`, one section:

1. **Website**: prompt "www.example.com", URL keyboard, no autocorrect or capitalisation. Under it, once it parses: "Fills only on **https://www.example.com**" (punycode in orange with the Shops warning line).
2. **Username or Email**: no autocorrect or capitalisation, `textContentType(.username)`, email keyboard on iPhone.
3. **Password**: `SecureField`, `textContentType(.password)` (the iOS key button opens the user's Passwords list; Crew has no associated domains, so nothing is suggested for the site and iOS has nowhere to offer saving it; checked on a real iPhone: no Save or Update Password sheet after Add or Edit), prompt "Required".

Footer: "Crew sends the password once to your Hermes server, which keeps it encrypted in Vera's vault. Crew doesn't store it." Edit adds: "Crew can't read the saved password, so enter it again."

Prefill: Edit fills Website (the host) and Username; Password starts empty. Return moves Website → Username → Password; Return in Password submits.

Validation (red footnote under the field, once it loses focus):

| Field | Rule | Message |
|---|---|---|
| Website | `shopHost(from:)` parses | "Enter the site's address, such as www.example.com." |
| Username | 1 to 256 characters after trimming, no line breaks | "Enter the username or email." |
| Password | 1 to 1024 characters | "Enter the password." |
| Website + Username | no other Hermes vault login (except the one being edited) has the same origin and username | "Vera already has this login for www.example.com." |

Blocking line at the top of the form (red): offline "You're offline.", `http` server "Saving a password needs an https connection to Hermes.", a failed `vault.add` "Couldn't save the login on the server." (the password field is already empty; the user types it again; the card reloads behind the sheet). After an edit's add succeeds and its remove fails, the sheet closes, the list reloads and shows both rows as duplicates.

Privacy, as the card sheet: iPhone covers the sheet with a material and `key.fill` while the scene is not active; Mac sets the sheet window's `sharingType = .none`; the form is `.privacySensitive()`.

## 1Password card

Title "1Password". One row with the state, a footnote and at most one button. Inputs: `vault.sources` (`onepassword`: `installed`, `enabled`, `unlocked`), `GET /api/env` (`is_set` for the token) and whether `vault.list` failed.

| State | Row | Footnote | Button |
|---|---|---|---|
| No saved token, CLI not installed | `key.horizontal` "Not set up" | "Give Vera its own 1Password vault. The server also needs the 1Password CLI." | **Connect…** |
| No saved token, installed, off for this bot (`enabled == false`) | "Turned off for Vera" | "1Password is turned off in Vera's Hermes settings." | none |
| No saved token, installed, on | "Not connected" | "Give Vera its own 1Password vault, readable with a token only Vera has." | **Connect…** |
| No saved token but `unlocked` | `checkmark.circle.fill` "Connected through the server's settings" | "Change this on the server." | none |
| Saved token, CLI not installed | "Token saved" | "Waiting for the 1Password CLI on the server." | **Disconnect…** |
| Saved token, off for this bot | "Turned off for Vera" | as above | **Disconnect…** |
| Saved token, `vault.list` failed | `exclamationmark.triangle.fill` (orange) "1Password didn't answer" | "Check that Vera's token is valid and can read its vault." | **Disconnect…** |
| Saved token, connected | `checkmark.circle.fill` (green) "Connected" | "Vera's 1Password logins show above. Change them in 1Password." | **Disconnect…** |
| Couldn't load | "Couldn't check 1Password." | | **Try Again** |
| Loading | small `ProgressView` | | |

The default bot shows the same states with no button and the footnote "Set up 1Password for the main bot on the server." With `terminal.backend` `local`, connected states add "Bots on this server could read the token and every login in its vault."

**Disconnect** asks: "Disconnect 1Password from Vera?", message "Vera can no longer sign in with its 1Password logins.", **Disconnect** (destructive) and Cancel. A `404` means the token was already gone. Errors: "Couldn't disconnect 1Password. Try again." in red under the button. After it the card and Logins reload. Offline: the last state stays; buttons disabled.

### Connect 1Password sheet

iPhone `.large` sheet with a grabber, Mac 400 pt wide. Title "Connect 1Password", **Cancel** and **Connect**.

1. Steps section (numbered rows): "In 1Password, create a vault for Vera, such as Crew · Vera, and keep Vera's logins there, each with its website.", "On 1Password.com, open Developer > Service Accounts and create one that can only read that vault.", "Paste its token below." When the CLI is not installed a fourth row: "Install the 1Password CLI (op) in the Hermes environment on the server."
2. **Service Account Token**: `SecureField`, prompt "ops_…", no autocorrect, no content type. Valid when it starts with `ops_` and is 20 to 4096 characters without whitespace: "Paste the token that starts with ops_." Footer: "Crew sends the token once to your Hermes server, which saves it in Vera's settings. Crew doesn't store it."

Same blocking lines (offline, http server), "Couldn't save the token on the server." on failure, the same privacy cover and Mac capture exclusion. On success the sheet closes and the 1Password and Logins cards reload.

## Shops card (moved)

Unchanged from [payments.md](payments.md#shops-inspector-info-tab) and [master-card.md](master-card.md#shops-card-inspector-info-tab-iphone-profile-page-and-mac-inspector-column), now in the Passwords tab, except the card row with crew-push 0.6.0 (`card_vault`):

- **One card:** a caption "Card used for new shops" (footnote, secondary) above the card art and "Shopping card •••• 4242", then Replace Card… as before. The default bot's "Kept here, never used to pay." line goes away: the card is no longer in any bot's vault.
- **Leftover cards** (`legacy_cards > 0`, default bot only): a footnote "1 older card is still in this bot's vault, and the bot can see it there. Remove it on the server." (plural "2 older cards are…"); the cleanup is in [docs/payments.md](../payments.md).
- Shop rows stay the bot's own copies; their footer is unchanged.

## Surfaces and directions

- **Crew to Hermes:** `vault.list`, `vault.sources`, `vault.add`, `vault.remove` over `/api/ws`; `GET /api/config`, `GET`/`PUT`/`DELETE /api/env` over REST, all behind the dashboard login. **Back:** metadata, `{id}`, `{removed}`, `{ok}`.
- **Bot:** a new or edited login is listed by `browser_vault list` on the bot's next call and filled on its exact origin; a removed one is gone; 1Password rows come and go with the token.
- **Chat:** Hermes' mid-chat login requests (`vault.save_login`, "save a login for this site") and code requests (`vault.code`) stay declined by Crew as today (PLAN: unrendered server requests answer 4404), so the bot is told no and says it could not sign in; the user adds the login in Passwords and asks again. Rendering them is a follow-up. The payment card, the shop offer above the composer and its Add Shop sheet are unchanged.
- **Other bots' inspectors:** logins are per bot. The master card row reads the same in every bot.
- **Bot list, push, groups:** nothing changes.
- **Default bot:** stops seeing "Shopping card" in `browser_vault list` after the migration.
- **iPhone and Mac, light and dark:** shared SwiftUI cards and sheets with system materials and secondary styles.

## Not in scope

Bitwarden, answering `vault.save_login` and `vault.code` in chat, adding or editing verification-code keys, showing which 1Password vault a row is from, turning a source on or off, address items, deleting leftover legacy cards from Crew, and #70 (the card on the device).

## Tests

- **crew-push (pytest):** migration moves one legacy master (crew-push vault has it, the default vault no longer does, same label and secret), is idempotent, finishes a half-done move, leaves several or a different legacy card alone and reports them as `legacy_cards`, never touches shop copies; `GET /payments`, Add Shop, Replace and Update Shops read and write crew-push's vault; `/status` lists `card_vault`; the card never appears in any response, log or file outside the vaults; version files agree at 0.6.0; the real Hermes `VaultStore` accepts the new directory in the integration test.
- **Crew unit (`CrewTests`):** decoding the recorded `vault.list` and `vault.sources` (real `crew-test` captures, scrubbed, plus contract-shaped fixtures with logins, 1Password rows with and without `identifier`, `allowed_origins` and an app origin, `has_otp`), the filter and sort, duplicates, identifier type inference, the `vault.add` params (keys, `https://` origin, label, the password only in `secret.password`, untrimmed), field validation, which actions each row offers (local, codes, 1Password), enabled controls per online/offline and http/https, every 1Password state row including the default bot, token validation, the env call refusing a redirect, `card_vault` and `legacy_cards`.
- **UI test (iOS Simulator, fixtures):** open the Passwords tab; Add Login with an invalid site shows the message after moving on; valid values enable Add; Add records one `vault.add` in the fixture log without the password, the sheet closes, and no save-password alert appears (a regression guard only: the Simulator never shows it without associated domains); a row's Remove asks and records one `vault.remove`; Connect 1Password records one env write without the token.
- **Renders** (iPhone and Mac, light and dark): `inspector-passwords` (logins incl. 1Password, codes, duplicate and long rows, 1Password connected, Shops with the caption), `inspector-passwords-empty` (no logins, not set up, no card), `inspector-passwords-error` (logins couldn't load, 1Password didn't answer), `inspector-passwords-offline`, `inspector-info` (Shops gone), `add-login`, `add-login-invalid`, `edit-login` (blocking error), `connect-1password` (CLI step), plus the Mac tab row at the 280 pt minimum and the iPhone tab row at an accessibility text size.
- **Real server:** read-only `vault.sources` and `vault.list` on `crew-test` (recorded, scrubbed). On `crew-test` only, with dummy values: add, edit and remove a throwaway login through the same RPCs and check `vault.list` after each; `PUT /api/env` a dummy `ops_` token, check `is_set` and `vault.sources` (`unlocked` follows the token only where `op` is installed), then `DELETE` it in the same probe and check `is_set` is false and a second `DELETE` answers `404`. No card, real login or real token is written anywhere. The bot direction (a crew-test chat's `browser_vault list` shows the new host, and not after Remove) needs a bot prompt, so the user checks it after the deploy, together with the device check above. After the user deploys crew-push 0.6.0: the Shops card still shows the card (migrated), the default bot's `vault.list` no longer lists it, and `legacy_cards` is 0.
