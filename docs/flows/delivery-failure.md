# Why a bot-to-bot message failed

Issue #121. When a `message_agent` delivery fails, Hermes (0.21.7, `tools/bot_failure_reasons.py`) attaches a typed `reason` next to the free-text `error`. Crew showed only "Not delivered" (mention peek) or nothing beyond the bot's own prose. Now each failure says what went wrong in plain language and whether trying again helps, like Messages' "Not Delivered" with its reason. There is no Retry button: the sender's bot, not the user, sent the message, so the user's next step is to ask again or fix the target bot.

## Where the reason arrives

- Immediately, in the `message_agent` tool result: `{"error": "...", "reason": "<code>"}`. Hermes runs its provider classifier over its own refusal text here ("No teammate named 'balance-bot'" comes back as `provider_quota_limit`), and no provider was called yet, so Crew trusts only `runtime_offline` (the relay's real refusal) on an immediate result. `{"status": "ambiguous", "error": ...}` means the outcome is unknown (recorded: the `@crew-test-old` turns in `Tests/fixtures/scenarios/delivery-failure/crew-test.preview.json`).
- Later, in the delivery follow-up notice (`[IMPORTANT: Background process proc_… exited (exit code 1). … Output:\n…]`). Parse rule: the last line of Output that parses as a JSON object (`{"error", "reason", "status": "failed" | "cancelled", …}`: live lane, `target_busy`, runner exceptions); otherwise the relay waiter's `Delivery to @x on y failed [reason: <code>]: <error>`; otherwise no code. JSON `status` `ambiguous`, `queued` or `claimed` (even with exit code 0) and the relay waiter's "No reply from … within" line mean the outcome is unknown. Delivered requires exit code 0 and, when there is JSON, `status` `settled`. Recorded on the real server: `Tests/fixtures/scenarios/delivery-failure/crew-test.history.json` (a throwaway `crew-test-*` target on a model its provider rejects; Hermes classifies that one as `unknown`).
- A local CLI turn that fails with raw provider prose has no code. Crew never classifies provider prose itself.
- Nothing emits `cancelled` as a reason or `agent_blocked` today (`cancel_queued_delivery` writes status `cancelled` with reason `runtime_offline`); they are mapped so a newer Hermes reads well.

## Copy

Headline by class, then one sentence. Hermes retries `runtime_offline`, `delivery_timeout`, `provider_rate_limit` and `provider_server_error` by itself, and `context_overflow` once after shortening the chat, so by the time Crew sees one of these that retry failed too. Crew also says "try again" for `target_busy`, `queued_expired` and `cancelled`, which pass with time; it never does for the rest.

| Class | Headline |
| --- | --- |
| No turn ran: `runtime_offline`, `queued_expired`, `target_busy`, `cancelled`, `target_scope_unresolved` | Not delivered. |
| The target got the message but its turn failed: every other known code | <Bot> couldn't answer. |
| `unknown`, missing, or a code Crew doesn't know | Message to <Bot> failed. |
| Outcome unknown (see above) | Delivery to <Bot> couldn't be confirmed. |

| Code | Sentence (`<Bot>` is the target's title) |
| --- | --- |
| `target_busy` | <Bot> is busy right now. Try again later. |
| `runtime_offline` | <Bot> is offline. Try again when it's back. |
| `delivery_timeout` | <Bot> didn't answer in time. It may have seen the message; try again if it matters. |
| `queued_expired` | <Bot>'s computer wasn't reachable in time. Try again when it's back online. |
| `cancelled` | The message to <Bot> was cancelled. Ask again if you still need it. |
| `provider_rate_limit` | <Bot>'s AI provider is limiting requests. Try again in a few minutes. |
| `provider_server_error` | <Bot>'s AI provider had an error. Try again later. |
| `provider_auth_or_access` | <Bot>'s AI provider rejected its login or access. Trying again won't help. |
| `provider_quota_limit` | <Bot>'s AI provider account has reached its usage limit. Trying again won't help. |
| `context_overflow` | <Bot>'s chat is too long to continue. Trying again won't help. |
| `missing_config` | <Bot> has no AI provider set up. Trying again won't help. |
| `model_unavailable` | <Bot>'s model isn't available. Pick another model for it; trying again won't help. |
| `agent_blocked` | <Bot> isn't taking messages. Trying again won't help. |
| `target_scope_unresolved` | Hermes couldn't load <Bot>'s settings. Trying again won't help. |
| unknown or unconfirmed | no sentence |

## Surfaces

One treatment everywhere: the headline in red (secondary when the outcome is only unconfirmed), the sentence in secondary text.

- **Mention peek** (tap a bot tag in the sender's bubble; iPhone sheet, Mac popover): the headline, then the sentence, or the server's error when there is no known code and it is one plain line (raw `HTTP 400: {…}` bodies are dropped). Fixes a lie: a follow-up that exited non-zero used to read "Delivered. The answer is in <Bot>'s chat."
- **Sender's chat, follow-up turn** (shown when the delivery failed or is unconfirmed, see `agent-messages.md`): under the bot's own acknowledgement, one footnote with the warning triangle: headline and sentence. No Retry button. The raw notice still never shows. A later reply from the same bot still hides an unconfirmed follow-up, as before.
- **Sender's chat, `message_agent` tool row** (immediate error, red cross): expanded, the sentence sits above the arguments and result where a live tool summary goes; only `runtime_offline` has one (see above), otherwise nothing new shows.
- **Target's chat (receiver)**: a failed incoming delivery is the usual collapsed "Message from <sender>" row; Hermes' own "Your request was not processed…" line is in its expanded log, with no Retry, as `agent-messages.md`'s "Failed or interrupted exchange" says. When the target's own reply back failed and its follow-up folds into the row, the footnote shows under the row, naming the bot it tried to reach.
- **Bot list** (preview, time, status, unread; iPhone and Mac): unchanged. The sender's preview is the bot's acknowledgement of the failure; the target's is "Message from <sender>". Failed comes only from the raw turn status or `session.active_list`, which this does not change.
- **Push**: unchanged. crew-push already pushes the sender's follow-up reply (the bot's own sentence about the failure).
- **Inspector**: no change.

## States

- Unknown or missing code: "Message to <Bot> failed." in the chat; the peek adds the server's error when it is short.
- Unconfirmed: "Delivery to <Bot> couldn't be confirmed." in secondary text, no advice (Hermes says not to resend).
- Target not in the roster (deleted throwaway, relayed bot): the handle stands in for the title; "the bot" when even the handle is unknown (the origin turn is outside the loaded window).
- Several failed deliveries: each follow-up carries its own footnote; the peek reads the one paired with that mention's process.
- Long server error: the peek keeps its two-line limit; the footnote wraps at large Dynamic Type sizes.
- Offline: rendered from the loaded transcript; nothing new.
- Light and dark: system red and secondary styles only.

## Tests

- `DeliveryFailureScenarioTests` on the recorded `delivery-failure` rows: the peek is Not delivered (was Delivered), the follow-up footnote, the bot rows' preview and status; the same rows with the code swapped (`target_busy`, `provider_auth_or_access`) for both headline classes; the recorded `ambiguous` immediate result as unconfirmed.
- Hand-built: every code has a sentence, `unknown` and new codes have none; the relay `[reason: x]` tag; Output with no shape; exit-0 `claimed` and the relay timeout as unconfirmed, exit-0 `settled` as delivered; an immediate `runtime_offline` refusal on the tool row and the peek; a misclassified immediate code ignored; the target's exchange row carrying its failed reply back (the `bot-mention` rows with a non-zero exit).
- Renders of the footnote on iPhone, light and dark.
