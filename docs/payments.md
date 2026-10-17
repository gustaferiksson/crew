# Payments: approve every purchase

Plan for [#9](https://github.com/gustaferiksson/crew/issues/9). Researched against Hermes **0.22.1** (the version mainframe runs). Nothing is built yet; each step below is one PR.

## Summary

- A bot pays with Hermes' built-in `browser_vault` tool. The card number is filled into the checkout page server-side and never enters the chat, the model or Crew.
- Every fill asks Hermes' approval gate (`surface: "vault-payment"`). Crew shows it as a payment card ("Pay at zalando.se?") with **Approve once** and **Deny** only. crew-push sends a time-sensitive push that expires after 300 s.
- The bot must state amount, merchant and reason, or crew-push blocks the fill. These are shown on the card and in the push. They are the bot's claim, not a check.
- One card per shop. The user types a shop's site in the bot's inspector; crew-push copies a **master card** into a new payment item bound to that exact origin. Nobody sees the number.
- The real spending cap is the issuer: a separate virtual card with a low monthly limit.
- Not supported: checkouts where the card fields live in an iframe (Klarna, Adyen, Stripe Elements). An upstream issue is filed.

## What Hermes 0.22.1 already does

- `browser_vault fill` on a `payment` item calls `_confirm_payment_fill`, which asks the session's approval surface. No answer, timeout, error, cron or `-q` all decline. Yolo, `approvals.mode: off` and session/always allowlists are ignored: every fill asks.
- A payment item fills only on its bound origin, checked again inside the fill script. An item without an origin is refused (`no_origin`).
- Filled values are registered with the redaction boundary, so a later tool result that echoes them exactly is scrubbed.
- The vault is per profile: `<profile home>/vault/vault.json.enc` plus `vault.key` (Fernet). Hermes' file tools refuse to read `vault/`.
- Crew can already call `vault.list` and `vault.remove` (with `profile`) over `/api/ws`. `vault.add` exists too, but it takes the card number from the client, so there is **no server-side copy**. Step 4 adds one.
- The approval Crew receives carries `command` ("Fill payment card '<label>' on <origin>"), `description`, `pattern_key: "mcp_elicitation"`, `request_id` and `choices`. It does **not** carry `surface`, and `choices` still offers `session` and `always`.
- Gaps: `resolve_gateway_approval` resolves the oldest pending approval when no `request_id` is given. So `/approve`, `/approve all` and a typed "yes" or "ok" on Telegram and other messaging platforms can approve a payment.

## Threat model

**Protected**

- The card number never reaches the model, the transcript, Crew or the push.
- No fill without a tap on Approve in Crew. No "allow for session", no "always". Until step 5, another client attached to the same session (TUI, Desktop) could still answer with `session` or `/approve`.
- A fill only runs on the exact origin the user added, and only from the bot's Bot Chat in Crew (step 2), so a typed reply on another platform cannot pay.
- A bot cannot add shops: the copy route sits behind the dashboard login (only true under `docker`, see the shell below).

**Not protected**

- **The amount.** Amount, merchant and reason are what the bot says. The approval covers the fill, not the cart: after a fill the bot can submit any total. The issuer limit is the only real cap.
- **Reading the card back after a fill.** Once the number is in the page, page scripts and `browser_cdp Runtime.evaluate` can read the fields and send them anywhere. Redaction only scrubs exact copies coming back to the model; reversed or split digits pass. Model-blind stops accidents, not a determined prompt injection.
- **Saved cards at the merchant.** If the shop stores the card, a later one-click purchase never calls `browser_vault`, so no approval fires and Hermes sees nothing. Mitigation: the bot is told never to tick "save card" (step 2), plus the issuer limit.
- **Look-alike domains.** Matching is exact, so `zalando-shop.se` never gets the `zalando.se` card. The risk is the user adding a wrong host because a bot asked. The inspector shows the host plainly and flags `xn--` (punycode) hosts.
- **Iframe checkouts.** The fill runs in the top document only. Card fields inside a cross-origin iframe are not found, so the fill fails with "no fields". It fails safe, but those shops cannot be used.
- **The bot's shell.** Under the `local` terminal backend a bot can read `vault.key` and decrypt every card. See [Open decisions](#open-decisions).
- **crew-push not loaded.** The stock gate still asks, but without amount, merchant, reason or the Bot Chat rule.

## Server commands

Hermes runs in a podman container on mainframe (quadlet `hermes.service`). Data is `/root/hermes/data` on the host and `/opt/data` (`HERMES_HOME`) inside the container. `mainframe` below is your ssh target and `<ctr>` the container name from `podman ps` (a quadlet without `ContainerName=` uses `systemd-hermes`). Note that `docs/push.md` still says `~/.hermes`; the paths here are the ones for mainframe.

Deploy crew-push (steps 2 and 4):

```sh
rsync -a --delete server/crew-push/ mainframe:/root/hermes/data/plugins/crew-push/
ssh mainframe systemctl restart hermes.service
```

## Steps

**Superseded for build order:** the experience and the crew-push/Crew contract are specified in [flows/payments.md](flows/payments.md) and [flows/payments-contract.md](flows/payments-contract.md), built as two parallel PRs (crew-push 0.4.0 with steps 1, 2 and the server half of 4; Crew with steps 3 and the inspector half of 4). Where they differ, the flow spec wins: Crew reads amount, merchant and reason from a crew-push route by `request_id` (not from `tool.start`, which carries only `{action, handle}` plus the extra args and is not sent when tool progress is off), answers payments with `approval.respond`, approves with a press and hold (no biometrics), and manages shops through crew-push routes rather than `vault.list`/`vault.remove`. Steps 5 and 6 are unchanged.


### 1. Test page and stock flow (S)

- **Changes:** `pages/checkout-test.html`: a static checkout with `autocomplete` card fields (`cc-number`, `cc-exp-month`, `cc-exp-year`, `cc-csc`, `cc-name`), a "Total 499 kr" line, a "Save card" checkbox and a Pay button that shows "Paid with card ending 4242". No network calls. Findings go into this doc.
- **Files:** `pages/checkout-test.html`, `docs/payments.md`.
- **Server:** Pages deploys only on a `v*` tag, so the page is live at `https://gustaferiksson.github.io/crew/checkout-test.html` after the next release. Then add the test card to crew-test by hand (the only time a card is added by hand):
  ```sh
  ssh -t mainframe podman exec -it <ctr> hermes -p crew-test vault add
  # kind payment, label Test 4242, origin https://gustaferiksson.github.io
  # card 4242424242424242, exp 12 / 2030, cvc 123
  ```
- **Verify on crew-test:** ask the bot to buy on the page. Crew shows the stock approval card; Crew closed gives a time-sensitive push; Allow Once fills the fields; Deny leaves the page empty and the bot does not retry; the transcript never contains `4242424242424242`. Record the exact approval params.

### 2. crew-push: payment gate and push (M, about 120 lines plus tests)

- **Changes in crew-push 0.4.0:**
  - `pre_tool_call` on `browser_vault` with `action: fill` and a `payment` handle (`backend_for_handle(handle).get_meta(handle).kind`) returns `{"action": "block", "message": ...}` unless the session is the profile's Bot Chat (`is_bot_chat`) and `amount`, `merchant` and `reason` are non-empty strings. The message tells the bot to retry with those args, never tick "save card" and never retry after a decline. Any exception blocks (fail closed). Valid args are kept per session. Hermes passes args that are not in the tool schema through to the hook untouched (`coerce_tool_args` skips unknown keys).
  - `pre_approval_request` with `surface == "vault-payment"` sends kind `payment`: title "Pay at <host>?", subtitle "<bot> · <card label>", body "<amount> · <merchant> · <reason>", category `CREW_APPROVAL`, time-sensitive, 300 s. No push actions yet.
  - `transform_tool_result` appends "Do not tick save card or remember card." to a successful payment fill.
- **Files:** `server/crew-push/crew_push/hooks.py`, `plugin.yaml` and `dashboard/manifest.json` (version and `provides_hooks`; CI checks they agree), `tests/test_hooks.py`, one line in `docs/push.md`.
- **Server:** deploy crew-push (above).
- **Verify on crew-test:** a fill without args shows the block text in the work log and the bot retries with args; the push reads "Pay at gustaferiksson.github.io?" with the amount; a fill from a second conversation of the same bot is blocked; `pytest` and CI green. Also confirm the bot's model keeps the extra args. If a provider drops them, the fallback is overriding the tool schema (`register_tool(override=True)`, which needs `plugins.entries.crew-push.allow_tool_override: true` in config).

### 3. Crew: payment card (M, about 150 lines)

- **Changes:** an approval with `pattern_key == "mcp_elicitation"` whose command starts with `Fill payment card '` is a payment. `PaymentCard` shows "Pay at <host>?", the card label, and amount, merchant and reason taken from the latest `browser_vault` `tool.start` arguments in the transcript (hidden if missing). Buttons: **Deny** and **Approve Once** (sends `once`). Rendered wherever approvals render (bot chats and group rooms), though step 2 only lets payments run in Bot Chat.
- **Files:** `Sources/Chat/RequestCards.swift`, `Sources/Chat/ChatSession.swift` (`ApprovalParams.patternKey`), `Sources/Groups/GroupSession.swift`, `Sources/Chat/ChatFixtures.swift` (snapshot `chat-payment`), a parser test in `Tests/`, a Decisions line in `docs/PLAN.md`.
- **Server:** none.
- **Verify:** `./build.sh` with no warnings; `./snapshot.sh chat-payment` light and dark; the step 1 flow on crew-test shows the payment card with the amount, also when Crew is opened cold from the push (if the in-flight `tool.start` is not replayed, the amount is hidden); `./device.sh`.

### 4. One card per shop (M, about 80 Python and 150 Swift lines)

- **Changes:**
  - crew-push 0.5.0 route `POST /api/plugins/crew-push/cards {profile, site}` (dashboard login required). It turns `site` into `https://<host>` (https only, no IPs or localhost, lowercase), refuses an origin the profile already has, reads the master card (the single `payment` item without origin in `get_default_hermes_root()/vault`; 409 if there are none or several), and calls `VaultStore(get_profile_dir(profile) / "vault").add_item(kind="payment", label="<master label> · <host>", origin=..., secret=<master secret>)`. Returns metadata only.
  - Inspector "Shops" section: lists the bot's payment items (`vault.list {profile}`), "Add shop website" calls the route, swipe to delete calls `vault.remove {profile, id}`. `xn--` hosts get a warning. If the bot's `terminal.backend` is `local` (`GET /api/config?profile=`), a footnote says other bots on the server can read the card.
- **Files:** `server/crew-push/dashboard/plugin_api.py`, `tests/test_routes.py`, version files; `Sources/Inspector/BotInspector.swift`, new `Sources/Inspector/Shops.swift`, `Sources/Inspector/InspectorSnapshots.swift`, a Decisions line in `docs/PLAN.md`.
- **Server:** add the master card once, to the launch profile's vault, with no origin. Use the 4242 test card until step 4 is verified, then replace it with the real virtual card. Remove the step 1 card. Deploy crew-push.
  ```sh
  ssh -t mainframe podman exec -it --user 10000:10000 -w /opt/hermes hermes /opt/hermes/.venv/bin/python -c '
  import getpass
  from pathlib import Path
  from agent.vault_store import VaultStore
  fields = ("card_number", "exp_month", "exp_year", "cvc", "cardholder_name")
  secret = {field: getpass.getpass(field.replace("_", " ") + ": ").strip() for field in fields}
  item = VaultStore(Path("/opt/data/vault")).add_item(kind="payment", label="Shopping card", secret=secret)
  print(item.id, item.label, item.origin)'
  ssh -t mainframe podman exec -it hermes hermes vault list
  ssh -t mainframe podman exec -it hermes hermes -p crew-test vault list
  ssh -t mainframe podman exec -it hermes hermes -p crew-test vault rm <id of Test 4242>
  ```
  `hermes vault add` cannot create the master in Hermes 0.22.1: it insists on an origin for payment items. The command above calls `VaultStore.add_item` without `origin` and reads the values hidden, so they never reach argv or the shell history. The vault files must stay owned by 10000 (`ssh mainframe chown -R 10000:10000 /root/hermes/data/vault` if not).

  If the default profile is a bot, it sees "Shopping card" in `browser_vault list` but cannot fill it (`no_origin`).
- **Verify on crew-test:** add `gustaferiksson.github.io` in the inspector, then the step 1 purchase works end to end; adding it twice, `http://` or an IP is refused; POST without a login gives 401; `hermes -p crew-test vault list` shows the copy with its origin.

### 5. Upstream Hermes PR and issue (S)

- **PR to NousResearch/hermes-agent:** `request_elicitation_consent` puts `surface` into the approval data, and for `vault-payment` also `allow_session: False, allow_permanent: False`, so clients get `choices: ["once", "deny"]`. `resolve_gateway_approval` skips `vault-payment` entries unless `request_id` matches, which closes `/approve`, `/approve all` and typed replies on every platform. Tests in `tests/tools/`.
- **Issue:** card fields in cross-origin iframes (Klarna, Adyen, Stripe Elements) are not fillable.
- **Server:** none until a release contains it; then the normal Hermes upgrade.

### 6. Crew: detect by surface (S)

- **Changes:** once mainframe runs a Hermes release with step 5, detect `surface == "vault-payment"` instead of the command prefix.
- **Files:** `Sources/Chat/ChatSession.swift`, `Sources/Chat/RequestCards.swift`, the parser test.
- **Verify:** the step 1 flow on crew-test still shows the payment card.

## Open decisions

### Where the bot's shell runs

Each bot can run shell commands. Today every profile uses `terminal.backend: local`, which means those commands run inside the Hermes container, as the same user as Hermes. From there everything in `/opt/data` is readable, including each `vault.key` next to its encrypted cards. One `cat` and a few lines of Python decrypt the master card and every copy. Hermes' file tools refuse the `vault/` folder, but the shell and `execute_code` do not. A bot only does this if a web page, email or message tricks it (prompt injection), or if the model misbehaves. This applies to every bot on the server, not just shopping bots, since they all share the same files.

With `terminal.backend: docker`, a bot's commands run in a separate sandbox container that only sees its own workspace, so the vault is out of reach. On mainframe this needs setup, because Hermes itself is a podman container. It has to start sibling containers through the host's podman socket: mount `/run/podman/podman.sock` into the Hermes container as `/var/run/docker.sock` (the image already has the docker CLI) and set `terminal.backend: docker` per profile. Workspace bind mounts are resolved on the host, so paths under `/opt/data` probably need to exist at the same path on the host. The data dir must never be listed in `docker_volumes`.

| Option | Protects the card | What it breaks or costs |
|---|---|---|
| A. Docker for shopping bots only | Barely. The other bots stay `local` and can still read the vault. Worse, with the podman socket mounted, a `local` bot can use it to get root on mainframe. | Setup above. |
| B. Docker for every bot | Yes. | Setup above, for every profile. Bots can no longer use tools or files of the Hermes container, background processes live in the sandbox, and each profile costs a running container. Every bot needs a quick check that its workflows still work. |
| C. Accept the risk | No. The worst case is one month's limit on the virtual card until it is frozen in the bank app. | Nothing. The inspector footnote from step 4 keeps the risk visible. |

**Recommendation: C now.** Keep the virtual card's monthly limit low (for example 1 000 kr) and freeze it when not shopping. Move to B if the limit grows or more bots browse untrusted sites. A alone is not worth the setup, because it adds a root path through the socket and still leaves the card readable.

**Planned hardening (with C):** only the "chief of staff" bot keeps a Hermes terminal (`local`, inside the podman container). Shopping bots keep just the browser and `browser_vault`, with the terminal, code-execution and browser console/CDP toolsets off, set per bot in the inspector's Toolsets (no code changes). The container isolates Hermes from mainframe, not bots from each other.
