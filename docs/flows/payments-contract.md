# Payments contract: crew-push 0.4.0 and Crew

The API behind [payments.md](payments.md). PR A (crew-push) implements it, PR B (Crew) consumes it; the JSON here is canonical and lands first as fixtures in `Tests/fixtures/payments/` (one file per example below), which both test suites read.

Conventions: routes live under `/api/plugins/crew-push/` behind the dashboard login, like the existing ones (Crew's cookie). Bodies are JSON. Errors are FastAPI's shape with a code: `{"detail": {"code": "<code>", "message": "<one line for logs>"}}`; Crew maps codes, never messages. Timestamps are Unix seconds (float). `profile` matches `^[a-z0-9][a-z0-9_-]{0,63}$`.

## Routes

### `GET /status` (extended)

Adds `"features": ["payments"]` and `"gate": true | false | null` (null: not reported yet). Crew asks for payment details only when `payments` is listed.

### `GET /payments?profile=scout`

Everything the Shops card needs.

```json
{
  "card": {"label": "Shopping card", "last4": "4242", "problem": null},
  "shops": [
    {"id": "vault_3f9a1c2b7d4e", "origin": "https://www.zalando.se", "host": "www.zalando.se",
     "created_at": 1760600000.0, "last_paid_at": 1760610000.0, "stale": false, "punycode": false}
  ],
  "terminal_backend": "local",
  "gate": true
}
```

- No usable master: `"card": {"label": null, "last4": null, "problem": "missing" | "several"}`. The master is the single `payment` item without origin in `get_default_hermes_root()/vault`. `last4` is computed inside the route; the number never leaves it.
- `shops`: the profile's `payment` items with an origin. `stale`: the copy's secret differs from the master's. `punycode`: a host label starts with `xn--`. `last_paid_at`: the newest `approved` entry for that origin in the log.
- `terminal_backend`: the profile's resolved `terminal.backend`, `local` when unset.
- Errors: `400 invalid_profile`, `404 unknown_profile`.

### `POST /payments/shops`

Request `{"profile": "scout", "site": "https://www.zalando.se/checkout?step=2"}`.

The route takes the host, IDNA-encodes a non-ASCII host, lower-cases it, and requires `https` (or no scheme), port 443 or none, a dotted public-looking name, not an IP literal and not `localhost`. Then it copies the master: `VaultStore(get_profile_dir(profile) / "vault").add_item(kind="payment", label="<master label> •••• <last4> · <host>", origin="https://<host>", secret=<master secret>)`.

- `201 {"shop": <shop>}`
- `400 invalid_site` with `"reason": "not_https" | "ip_address" | "localhost" | "no_host" | "port"` inside `detail` (`localhost` also covers a single-label name such as `intranet`)
- `409 duplicate_shop`, `409 no_card`, `409 several_cards`, `404 unknown_profile`

### `DELETE /payments/shops/{id}?profile=scout`

Removes a `payment` item with an origin (never the master, never another kind). `200 {"removed": true}`, `404 unknown_shop`.

### `GET /payments/requests/{request_id}`

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
  "decided_at": null,
  "now": 1760609941.2
}
```

- `state`: `pending | approved | denied | expired | cancelled`, from Hermes' `post_approval_response` `choice`: `once`/`session`/`always` → approved, `deny` → denied, `timeout` → expired, `cancelled`/`notify_failed` → cancelled.
- `fill`: `null` until the tool returns, then `filled | not_filled`. `fill_error`: `null | no_fields | origin_mismatch | origin_changed | human_has_control | error`.
- `card_label` without the ` · <host>` suffix. `now` is the server clock, for the countdown.
- `session_key` and `tool_call_id` are stored in the log but not returned.
- `404 unknown_request`. The entry is written synchronously in `pre_approval_request`, which Hermes fires before it sends the `approval` frame (`approval_gateway_wait.py:203-205`), so a 404 is final after **one** retry (300 ms, for file-write latency).
- Crew shows Hold to Pay only when `origin` equals the origin in the approval's `command` and `card_label` equals the command's label minus the host suffix.

## Answering

Crew answers a payment with the RPC `approval.respond {"session_id": <runtime id>, "choice": "once" | "deny", "request_id": <32 hex>}`, not the server-request response frame. It is the path that makes Hermes send `request.cancel {reason: "resolved"}` to other attached clients. `{"resolved": 1}` is success; `{"resolved": 0}` means already answered or expired (Crew then reads the state from the route); error `4001` means the session is gone, `5004` a server error. Never `session` or `always`. Other approvals keep the response frame.

The push Deny action uses the same RPC through push.md 5.6's action transport (ticket, connect, capabilities, respond, disconnect). `approval.respond` finds the session by `request_id` when the runtime id is stale (`methods_prompt.py:1424-1451`).

## Hooks

State shared across processes lives in files: `gate.json` and `payments.json`. Only the claim keyed by `tool_call_id` stays in memory, because `pre_tool_call`, `pre_approval_request` and `transform_tool_result` run in the same agent thread for one call. PR A confirms on `crew-test` which process runs Crew's Bot Chat hooks.

### `pre_tool_call`

On `browser_vault` with `action == "fill"` and a handle whose item is `payment`. This branch is **not** wrapped in crew-push's `quiet`: it catches its own exceptions and returns a block with `crew_check_failed` (also when the item's kind cannot be read, such as a locked password manager). Checks, in order; the first failing one returns `{"action": "block", "message": <JSON string>}`:

| Code | Rule |
|---|---|
| `crew_gate_off` | `gate.json` does not say `auth_required: true`. Every crew-push route request writes `request.app.state.auth_required` there; Crew calls `/status` on every authenticated connect, whether or not notifications are allowed. The dashboard removes `gate.json` when it loads crew-push, so a restart without the login cannot inherit an old `true`. |
| `crew_not_bot_chat` | `session_id` is empty or not the profile's Bot Chat (`is_bot_chat`). |
| `crew_one_at_a_time` | A payment for this session is `pending` in the log, or any pending approval in the session (`list_gateway_approvals(session_key)`, key from `tools.approval_context.get_current_session_key()`) has the same `command` this fill will raise. |
| `crew_after_decline` | A decline blocks retries only within the turn it happened in. Blocks while this session's newest payment is `denied` or `expired` and no user turn has started in that session since its `decided_at`; the user's next message lifts it, so "try again" in a new message works. A user turn is a `pre_llm_call` whose message is not agent-shaped (`message_agent`), delivery-shaped or a bracketed system note, remembered per `session_id`. Crew's hidden prompts (`<a2ui-action>…</a2ui-action>` answers and "I added … to your shops. Continue the purchase.") count as user turns, since Crew sends each only after the user's tap. The message tells the bot all of this: "The user declined a payment in this turn, so fills are blocked until the user sends a new message. Do not retry now. If they ask you to try again in a new message, you may." |
| `crew_missing_details` | `amount`, `merchant` or `reason` is missing, empty after cleaning, longer than 32/64/140, or `amount` has no digit. The message names the three args with an example. |
| `crew_no_shop_card` | Hermes' own `_focus_bound_origin(task_id, item.origin, "payment")` finds no tab on the item's origin. Adds `missing_shop` (the current origin) only when the current page has card fields. Skipped if the browser cannot be read; Hermes' check still refuses. Without `missing_shop` it also covers an iframe checkout on the item's origin (the probe sees no card fields in the top document), so the user is never asked. |

Cleaning: strip Unicode Cc and Cf, collapse whitespace, trim. Unknown args reach the hook because `coerce_tool_args` skips keys not in the schema (`arg_coercion.py:40-43`). On allow, the hook snapshots the session's pending `request_id`s and remembers `{claim, item origin, label, snapshot}` by `tool_call_id`, then returns nothing.

Hermes delivers a block to the model and the transcript as `{"error": "<message>"}` (`model_tools.py:787-788`), capped at 2048 characters, and does not run `transform_tool_result` on it. The message is itself JSON, so Crew decodes `error` a second time:

```json
{"error": "{\"success\": false, \"error_type\": \"crew_no_shop_card\", \"crew_payment\": {\"missing_shop\": \"https://www.zalando.de\"}, \"error\": \"There is no card for https://www.zalando.de. Tell the user they can add this shop in Crew, then wait.\"}"}
```

### `pre_approval_request`

Only for `surface == "vault-payment"`, and ignored when `coalesced=True`. It finds the claim by `tool_call_id`, then the one pending entry for `session_key` that is not in the claim's snapshot and whose `command` equals the hook's. Exactly one match: write the log entry (`pending`, `expires_at` from `approvals.timeout`) and send the `payment` push. Anything else: write nothing, so Crew shows the Deny-only card. The generic `approval` push is not sent for a payment.

### `post_approval_response`

For `vault-payment` and not `coalesced`: set `state` and `decided_at` on the entry with the matching `command` and session, then send `payment_resolved` to every device.

### `transform_tool_result` (fail-open in Hermes; Crew has a fallback)

- **`fill` on a payment item:** returns Hermes' result with `"crew_payment": {"request_id", "origin", "state", "fill", "fill_error"}` added (`origin` is the shop the user was asked about, so a denied, expired or cancelled receipt can name the host although Hermes' raw `payment_declined` result carries no origin), and the bot's `error` text replaced by state: denied, "The user denied this payment. Do not retry in this turn; ask what they want instead. If they ask you to try again in a new message, you may."; expired, "Nobody answered within 5 minutes. Tell the user it expired. Do not retry in this turn; if they ask again in a new message, you may."; cancelled, "The request was cancelled. Stop." A success without `cc-number` in `fields` becomes `"success": false` with `fill_error: "no_fields"` and "The card fields weren't found; this checkout probably puts them in a payment frame, which can't be filled. Tell the user." A real success gets "Click the shop's pay button. Never tick save card or remember card." It also writes `fill` and `fill_error` to the log.
- **`list`:** when the current page has card fields (Hermes' `_TAB_PROBES["payment"]` selector, evaluated on the page) and no payment item in this profile has that origin, adds `"crew_payment": {"missing_shop": "<origin>"}` and a `hint` to ask the user to add the shop in Crew.

Decorated fill result (fixture `fill-approved.json`):

```json
{"success": true, "filled_fields": 5, "backend": "local", "kind": "payment", "origin": "https://www.zalando.se",
 "fields": ["cc-csc", "cc-exp-month", "cc-exp-year", "cc-name", "cc-number"],
 "crew_payment": {"request_id": "5f0c3e9a2b7d4c18a6e1f20b9d3c7a54", "origin": "https://www.zalando.se", "state": "approved", "fill": "filled", "fill_error": null},
 "next": "Click the shop's pay button. Never tick save card or remember card."}
```

### Log

`plugin-data/crew-push/payments.json`: a JSON list, newest last, at most 200 entries, written under the same lock and atomic replace as `devices.json`. No card data beyond the last four inside `card_label`. `gate.json`: `{"auth_required": true, "seen_at": 1760600000.0}`.

## Push payloads

`payment` (fixture `push-payment.json`):

```json
{
  "aps": {
    "alert": {"title": "Scout", "subtitle": "Pay at www.zalando.se?", "body": "499 kr · Zalando · Winter boots, size 43"},
    "sound": "default", "thread-id": "profile.scout", "category": "CREW_PAYMENT",
    "interruption-level": "time-sensitive"
  },
  "crew": {"v": 1, "kind": "payment", "install_id": "9f2c41d07ab35e11", "profile": "scout",
           "session_id": "20261016_101512_ab12cd", "event_id": "d53856b2866653ae",
           "request_id": "5f0c3e9a2b7d4c18a6e1f20b9d3c7a54", "expires_at": 1760610240.0}
}
```

Headers: `apns-push-type: alert`, `apns-priority: 10`, `apns-expiration: <expires_at>`, `apns-collapse-id: payment.<sha256(request_id)[:16]>`. Pref `approvals`. Previews off: no subtitle, body "Wants to pay".

`payment_resolved` (fixture `push-payment-resolved.json`), to every device:

```json
{"aps": {"content-available": 1},
 "crew": {"v": 1, "kind": "payment_resolved", "install_id": "9f2c41d07ab35e11", "profile": "scout",
          "request_id": "5f0c3e9a2b7d4c18a6e1f20b9d3c7a54", "state": "approved"}}
```

Headers: `apns-push-type: background`, `apns-priority: 5`, `apns-expiration: now + 3600`, `apns-collapse-id: payment-resolved.<sha256(request_id)[:16]>`. Crew removes delivered notifications whose `crew.request_id` matches.

## Error codes

| Where | Code | Crew shows |
|---|---|---|
| `GET /payments` | `invalid_profile`, `unknown_profile` | "Couldn't load shops." |
| `POST /payments/shops` | `invalid_site` + `not_https` / `ip_address` / `localhost` / `no_host` / `port` | under the field: "Use an https address." / "Use a name, not an IP address." / "That isn't a public website." / "Enter a website." / "Use the standard https port." |
| | `duplicate_shop` | "www.zalando.se is already a shop." |
| | `no_card`, `several_cards` | the card row's states |
| `DELETE` | `unknown_shop` | the row leaves (already gone) |
| `GET /payments/requests/{id}` | `unknown_request` | Deny-only card |
| tool results | `crew_gate_off`, `crew_not_bot_chat`, `crew_one_at_a_time`, `crew_after_decline`, `crew_missing_details`, `crew_no_shop_card`, `crew_check_failed` | only `crew_no_shop_card` with `missing_shop` drives UI (the offer); the rest are failed tool rows and the bot's words |
| `approval.respond` | `resolved: 0`, `4001`, `5004` | state from the route; card leaves; "Couldn't reach Hermes. Try again." |
| any 5xx or network | | "Couldn't load the amount." + Try Again; "Couldn't load shops." |

## Fixtures

`Tests/fixtures/payments/`: `status.json`, `payments.json`, `payments-no-card.json`, `payments-several.json`, `shop-created.json`, `shop-removed.json`, one error file per route code (`error-<code>.json`, and `error-invalid-site-<reason>.json` per reason), `request-pending.json`, `request-approved.json`, `request-expired.json`, `approval-frame.json` (reconstructed from Hermes 0.22.1's `ServerRequest.frame()` and `_approval_request_payload`; re-record it on `crew-test` after the deploy), `block-no-shop-card.json`, `block-missing-details.json`, a decorated and a raw fill result per outcome in the Results table (`fill-<outcome>.json` and `fill-<outcome>.raw.json` for `approved`, `denied`, `expired`, `cancelled`, `origin-changed`, `origin-mismatch`, `no-fields`, `no-card-number`, `human-has-control`, `error`), `list-missing-shop.json`, `push-payment.json`, `push-payment-previews-off.json`, `push-payment-resolved.json`.
