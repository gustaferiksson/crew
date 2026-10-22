# Why a bot-to-bot message failed

Issue #121. When a `message_agent` delivery fails, Hermes (0.21.7, `tools/bot_failure_reasons.py`) attaches a typed `reason` next to the free-text `error`. Crew showed only "Not delivered" (mention peek) or nothing beyond the bot's own prose. Now each failure says why in plain language and whether trying again helps, like Messages' "Not Delivered" with its reason, without a Retry button: the sender's bot, not the user, sends the message, so the user's next step is to ask again or fix the target bot.

## Where the reason arrives

- Immediately, in the `message_agent` tool result: `{"error": "...", "reason": "<code>"}` (a bad target, a relay refusal such as `runtime_offline`), or `{"status": "ambiguous", "error": ...}` with no code.
- Later, in the delivery follow-up notice (`[IMPORTANT: Background process proc_… exited (exit code 1). … Output:\n…]`): the output is one JSON line `{"error", "reason", "status": "failed", …}` (live lane, `target_busy`, runner exceptions) or the relay waiter's `Delivery to @x on y failed [reason: <code>]: <error>`. Recorded on the real server: `Tests/fixtures/scenarios/delivery-failure` (a throwaway `crew-test-*` target on a model its provider rejects; Hermes classifies that one as `unknown`).
- A local CLI turn that fails without either shape (raw provider prose) has no code. Crew never classifies provider prose itself.

## Copy (one mapping, Hermes' retry policy)

Retrying helps for Hermes' `AUTO_RETRYABLE` codes plus `target_busy`, `queued_expired` and `cancelled`; never for the rest.

| Code | Text (`<Bot>` is the target's title) |
| --- | --- |
| `target_busy` | <Bot> is busy right now. Try again in a moment. |
| `runtime_offline` | <Bot> is offline. Try again when it's back. |
| `delivery_timeout` | <Bot> didn't answer in time. Try again later. |
| `queued_expired` | <Bot> didn't pick up the message in time. Try again. |
| `cancelled` | The message to <Bot> was cancelled. Send it again if you still need it. |
| `provider_rate_limit` | <Bot>'s AI provider is limiting requests. Try again in a few minutes. |
| `provider_server_error` | <Bot>'s AI provider had an error. Try again later. |
| `provider_auth_or_access` | <Bot>'s provider login expired or lost access. Sign in again on the server; trying again won't help. |
| `provider_quota_limit` | <Bot>'s provider account is out of credit. Trying again won't help. |
| `context_overflow` | <Bot>'s chat is too long to continue. Clear its chat, then try again. |
| `missing_config` | <Bot> has no AI provider set up. Trying again won't help. |
| `model_unavailable` | <Bot>'s model isn't available. Pick another model for it; trying again won't help. |
| `agent_blocked` | <Bot> can't take messages right now. Trying again won't help. |
| `target_scope_unresolved` | Hermes couldn't load <Bot>'s settings. Trying again won't help. |
| `unknown`, missing, or a code Crew doesn't know | no reason sentence; the server's short error text where a surface already showed it |

## Surfaces

- **Mention peek** (tap a bot tag in the sender's bubble; iPhone sheet, Mac popover): "Not delivered" in red, then the reason sentence in secondary text, or the server's error when there is no known code (two lines, as before). Fixes a lie: a follow-up that exited non-zero used to read "Delivered. The answer is in <Bot>'s chat."; it now reads "Not delivered".
- **Sender's chat, follow-up turn** (shown only when the delivery failed, see `agent-messages.md`): under the bot's own acknowledgement, one red footnote with the warning triangle, the same style as a failed turn: "Not delivered. <reason sentence>", or "Not delivered to <Bot>." without a known code. No Retry button. The raw notice still never shows.
- **Sender's chat, `message_agent` tool row** (immediate error, red cross): expanded, the reason sentence sits above the arguments and result in red, where a live tool summary goes; without a code nothing new shows (the raw result is already there).
- **Target's chat, exchange row**: when the target's own follow-up (its reply back to the sender) failed and folds into the exchange row, the same footnote shows under the row, naming the bot it tried to reach.
- **Bot list** (preview, time, status, unread; iPhone and Mac): unchanged. The preview is the last visible turn, which is the bot's acknowledgement of the failure; Working and Failed come from the raw turn status, which this does not change.
- **Push**: unchanged. crew-push already pushes the sender's follow-up reply (the bot's own sentence about the failure).
- **Inspector**: no change.

## States

- Unknown or missing code: "Not delivered to <Bot>." in the chat, the server's error in the peek. Never a guess.
- Target not in the roster (deleted throwaway, relayed bot): the handle stands in for the title.
- Several failed deliveries: each follow-up carries its own footnote; the peek reads the one paired with that mention's process.
- Long server error: peek keeps its two-line limit; the chat footnote is one sentence and wraps at large Dynamic Type sizes.
- Offline: rendered from the loaded transcript; nothing new.
- Light and dark: system red and secondary styles only.
