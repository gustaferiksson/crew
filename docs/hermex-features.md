# Hermex research (for Crew)

Researched 2026-10-13. Hermex is open source (MIT), so nearly everything below is confirmed from its repo at `master` (latest release v1.8.0 on GitHub, 1.9 on the App Store), not inferred from screenshots. Where a claim is my inference it is marked **[inference]**.

Key sources:
- Repo: https://github.com/uzairansaruzi/hermex (README, CHANGELOG.md, CONTEXT.md, TESTFLIGHT.md, HERMES_AGENT_TESTED_SHA)
- Bot Mode spec (2,675 lines, the main source): https://github.com/uzairansaruzi/hermex/blob/master/docs/agents/bots.md
- Push design: https://github.com/uzairansaruzi/hermex/blob/master/docs/agents/push.md
- Push plugin + relay: https://github.com/uzairansaruzi/hermex-push
- App Store: https://apps.apple.com/app/hermex/id6767006319
- Website: https://hermexapp.com/
- Nous's Bot Mode (Desktop plugin, now built in): https://github.com/NousResearch/Hermes-Bot-Mode and `apps/desktop/src/plugins/hermes-bots/` in https://github.com/NousResearch/hermes-agent
- Grok Bot: https://x.ai/news/introducing-grok-bot, https://docs.x.ai/grok-bot, https://docs.x.ai/grok-bot/mobile, https://docs.x.ai/grok-bot/settings-and-notifications

## 0. The one distinction that matters: Hermex has two backends

`ServerAccount.kind` is either:

1. **Webui server**: the third-party `nesquena/hermes-webui` Python server (port 8787, `HERMES_WEBUI_PASSWORD`, cookie sign-in, `/api/chat/start`, `/api/chat/stream` SSE, `/api/crons`, `/api/session/*`...). This was Hermex's original and still default path; it opens on the session list. Crew will not talk to this, so it is ignored below except where UX is shared.
2. **Hermes server**: Hermes Agent's own `hermes dashboard` (port 9119), reached directly over HTTP + a JSON-RPC WebSocket gateway. It opens on the **Bots inbox**. This is "Bot Mode" and is exactly what Crew is building against. Everything in `bots.md` is this path. (Source: CONTEXT.md "Servers", bots.md lines 1-56.)

Bot Mode is gated behind Settings → "Bot Mode (beta)", off by default (`BotModeGate`, one app-wide `@AppStorage` bool). Since 1.9 a Hermes host can be added as its own server from onboarding or Settings, and its home has two sides: Bots and Sessions. There is an open epic (#707, #1218 "Move to Hermes") to migrate webui users onto the Hermes dashboard, so the author is clearly moving toward the dashboard path. **[inference]**

Platforms: iPhone, iPad, visionOS (iPad app). No macOS target in the tree. Issue #13 ("macOS app Phase 1") is closed as completed but nothing named HermesDesktop exists at HEAD; #200 "Make the iPad app available on macOS and visionOS" is open. iOS 18+.

## 1. Feature list

### 1a. Confirmed, general (both backends unless noted)
From README, App Store and CHANGELOG 1.0 to 1.9:
- Streaming chat with thinking + tool-call detail, steer / queue / stop mid-run.
- Sessions: browse, search (multi-word, any order), resume, pin, archive (with Undo toast), rename, delete, duplicate, export JSON, fork ("Forked from" row linking to parent), unread dots, Working / Input / Approval row states.
- Model picker with provider glyphs, recents and **favourite models**; reasoning effort per session; Fast toggle; Profile chip; folder (cwd) chip.
- Profiles and projects (on Hermes: projects are folder sets, `projects.tree/create/update/delete`).
- Tasks (cron): agenda list, filters, Run Now, per-task run history, editor with model/provider/profile/skills/delivery target.
- Skills: browse, search, toggle, read SKILL.md and linked files.
- Kanban boards (statuses Triage → Archived, dispatcher preview/run, bulk actions, live updates).
- Workspace file browser, syntax-highlighted source viewer, Git review surface (stage/commit/push/branch).
- Memory (read-only) and Usage/Insights (chart, provider account limits).
- Attachments: camera, custom photo picker, files; share extension; Quick Look for PDFs/Office up to 25 MB.
- Voice: composer dictation (on-device or server), "New Chat with Voice" App Intent, "Listen" TTS (server voice via `/api/audio/speak`, falls back to on-device).
- Live Activities (Lock Screen / Dynamic Island) for running turns with tool counts.
- Optional push via `hermex-push` plugin + relay (see section 2).
- App lock with Face ID (1.9), alternate app icons, themes, header logo colour, 17 languages, RTL.
- Multi-server switching (1.3), per-server isolation of caches, drafts, keys (`docs/agents/multi-server-state-isolation.md`).
- Offline: read-only cached sessions/transcripts.
- App Intents / Shortcuts ("New chat in profile"), deep links (`hermes-agent://`).
- iPad: sidebar, keyboard shortcuts, ↑ to recall last message.
- Settings toggles to hide unused parts (Tasks, Kanban, Skills, Memory, Insights, Active Profile, Projects, chat Files button, Git actions).

### 1b. Bot Mode ("bots" beta), confirmed from bots.md

**What a bot is.** A bot **is a Hermes profile** (confirmed on both sides: bots.md and the Nous Hermes-Bot-Mode README: "A bot is a Hermes profile: isolated config, memory, skills, credentials, and chat history under `~/.hermes/profiles/<name>/`"). The roster is `profiles.list`. `default` displays as "Hermes".

**A bot's chat** is one canonical session per profile titled exactly `"Bot Chat"`, created hidden: `session.create {profile, title: "Bot Chat", hidden, follow_profile_config}` then `session.title` so the row persists before any prompt. It is found by exact-title `session.list` on every attach ("adopt before mint", same as Desktop). Since #1148 it opens in the normal Hermes chat screen (`.canonicalChat(profile)` target), with some commands refused (`/new`, `/clear`, `/branch`, `/fork`, `/title`, `/undo`, `/retry`, `/resume`, `/sessions`), and no Edit/Regenerate/Fork.

**Bot identity / metadata.** Everything lives in the profile's `ui_meta["hermes-bots"]` object, shared with Hermes Desktop: title (display name), description (role), `shape`, `color`, `custom`/`imageKind`, `pinned`, `hidden`, `sectionId`, `sectionName`, plus a Hermex-only `expression` key that Desktop preserves but ignores. Writes go through `profiles.configure` with the whole object as received plus changed fields, guarded by `ui_meta_expected_revisions["hermes-bots"]` (optimistic concurrency; conflict → re-read and notice). Title fallback order: `ui_meta` title → core `display_name` → profile name. **Crew should read and write the same keys to interoperate with Desktop and Hermex.**

**Avatar system** (`HermesMobile/Features/Bots/BotProfileAppearance.swift`):
- 8 shapes: circle, blob, squircle, pill, triangle, hexagon, cloud, drop.
- 11 swatches: Auto (`#ffffff`, adaptive: white in dark mode, black in light, eyes inverted), Brown `#a9703d`, Red `#ef4444`, Orange `#f97316`, Amber `#f59e0b`, Green `#22c55e`, Teal `#14b8a6`, Blue `#38bdf8`, Purple `#8b5cf6`, Pink `#ec4899`, Gray `#8e8e93`.
- 16 expressions (eye geometries "after Bloub"): neutral, attentive, surprised, excited, happy, laughing, angry, sad, scared, wary, confused, curious, proud, shy, bored, sleepy. Unknown reads as neutral.
- Photo: separate `profiles.set_asset` write (JPEG, ≤ 2 MB decoded) after the metadata write; read via `profiles.get_asset` only for rows flagged `has_avatar`, cached in memory keyed by connection UUID + profile + look revision.
- Desktop's blobatars, pets and AI-generated portraits are Desktop-only; Hermex falls back to the static shape. (Nous README says Desktop has "7 shapes × 10 colors", image upload, AI portrait via `image.generate`, and a pixel pet; Hermex extended shapes/colours/expressions.)
- Motion: faces blink every 3 to 5 s (seeded by profile name). The open bot's title face plays a 15 fps "working" sway for 30 s from turn start then holds a still lean. State faces override the pinned expression in the chat title: **Curious** while waiting on you, **Sad** after a failed turn (VoiceOver: "Needs attention" / "Turn failed"). Inbox rows, tiles, chips and Live Activity keep the pinned expression.
- Create/edit hero face (`BotInteractiveFaceView`): eyes follow a dragged finger, tap squishes to surprised, random "bits" every 4 to 9 s (glance, double blink, wobble, hop, spin), and reacts to edits (hop on shape change, wobble on colour, glance down while typing the name). Reduce Motion stills everything.

**Inbox layout and favourites.**
- "Favourites" = Desktop's `pinned`: pinned bots sit **above the list as large avatar tiles with the name beneath** and appear nowhere else.
- Rest grouped by Desktop sections (`sectionId`/`sectionName`), sorted A–Z; unfiled bots and all group rooms form a final block headed "Other chats" when named sections exist. "Move to Section", "New Section…", "Remove from Section", "Reorder Sections…" (phone-local order in UserDefaults).
- Hidden bots excluded unless revealed (dimmed, own section) or matched by search.
- Within each group: waiting → working → unread → newest.
- Row: avatar, name, role chip (description ≤ 24 chars), preview, date label (time today / weekday / month-day). Status word "Waiting for you" or "Working" replaces the date and sits under a pinned tile's name.
- Long-press menu: Pin/Unpin, Hide/Unhide, Move to Section, Edit, Duplicate, Delete.
- Home bottom bar: `(filter) [Bots | Sessions] (new chat)`. Header "HERMEX" plus a pill with search and the server avatar (tap Settings, hold to switch servers).
- Unread for bots is device-local (last seen `last_active` per profile in UserDefaults); unread for sessions is host-side (`PATCH /api/sessions/{id} {unread}` shared with Desktop).
- Live status: `session.active_list {}` after every roster read, matched to the bot by canonical chat `session_key`; re-polled every 5 s while any bot is busy. Roster reloads are pushed by the gateway's `sessions.changed` event (coalesced).

**Bot lifecycle.** Create: name → slug (`[a-z0-9][a-z0-9_-]{0,63}`), optional description, model+provider, credential switch (`share_auth: true` default, or `mirror_credentials: false`), then `profiles.create` → `profiles.configure` (look) → canonical chat. Duplicate uses `clone_from` (config, skills, SOUL.md; not photo or organization). Delete is REST `DELETE /api/profiles/{name}` (no RPC exists); `default` undeletable. Editor: `profiles.describe` gives role, full SOUL instructions, pinned model, skills, toolsets, MCP servers; save is per-section `profiles.configure`; expensive model needs `confirm_expensive_model`.

**Mentions.** `@` in a bot chat lists up to 8 other bots (plus workspace files from `complete.path`). Mentions do not deliver; at send the phone appends Desktop's identification note and the agent decides to call its server-side `message_agent` tool. Chips render with avatar + name.

**Group rooms.** `groups.*` RPCs (capabilities, list, state, log, send, approve, retry, stop, create, rename, disband). 2 to 6 bots, members frozen at creation, threads, Stop for the whole room, approvals limited to once/deny, welcome screen with all members' faces. Polled every 2 s working / 10 s idle while visible.

**Requests that park a bot** (JSON-RPC server requests with string ids): `clarify`, `approval`, `sudo`, `secret`, `vault.*`, `terminal.read`, `window.read`, `preview.read`, `preview.act`, `tour`. Answer with `request.answer`, `approval.respond`, `clarify.lock`. Connection/connector operations via `connection.respond`. Approvals show the host's own choices (once/session/always/deny) with a scope sentence.

**Search.** Sheet with All / Bots / Messages filter; bot chats searched on the host (`GET /api/sessions/search` per profile, FTS snippets with `>>>`/`<<<` marks), room messages from a local cache.

**Notifications.** Optional push (section 2), per-server settings: replies, subagents, previews, "Quiet the Open Chat", Time Sensitive approvals. Banners name the bot. Without push: local run-complete alerts and Live Activities.

**Reactions.** App Store 1.8 notes and CHANGELOG say "Tapback reactions that sync with Hermes Desktop". bots.md at HEAD says "Hermex shows no reactions (#1147)" and the Bot Chat screen was removed (#1148). **I treat HEAD docs as current**: reactions were shipped then removed when bot chats merged into the main chat.

### 1c. Onboarding / login flow (confirmed)
1. Welcome → features page.
2. "Set up Hermes" page: a copyable prompt you paste into your own agent (it configures the server; text in section 2). Toggle to the webui prompt instead. A reminder blocks Continue until copied or skipped.
3. Optional Tailscale page (App Store link).
4. Connect form: connection mode (Same Wi-Fi / Private network / Cloudflare Tunnel, only changes placeholder and help; Cloudflare adds empty `CF-Access-Client-Id/Secret` header rows), address, custom headers. First Connect probes public `GET /api/status`; a JSON object with `auth_required` means Hermes dashboard, so username + password appear; second Connect signs in. Anything else falls through to the webui path.
   - Schemeless address → HTTPS, except private/Tailscale IPs, `.local`, single-label → HTTP. Pasted links trimmed to root. No TLS downgrade.
   - Errors are specific: unreachable, `400 Invalid Host header` → set `dashboard.public_url`, Cloudflare/proxy sign-in in the way, browser-only sign-in, refused WS upgrade, outdated host (< 0.21.3).
   - Host identity: `install_id` from `/api/status`, trust on first use; a different id later fails before sending the password.
5. Credentials in Keychain per server.

## 2. How it talks to Hermes (Hermes server path)

### 2a. Sign-in and socket (confirmed: `Networking/Hermes/HermesConnection.swift`, `HermesREST.swift`, bots.md 80-237)
1. `GET /api/status` (public): `auth_required`, `auth_providers` (must contain `basic`), `install_id`, `version`, gateway state, platform counts.
2. `POST /auth/password-login {provider: "basic", username, password}` → session cookie (ephemeral jar).
3. `GET /api/auth/me` → verify `provider == basic`.
4. `POST /api/auth/ws-ticket` → single-use ticket per socket.
5. WebSocket `GET /api/ws`, `Sec-WebSocket-Protocol: hermes-gateway-v1, <ticket>`. JSON-RPC 2.0 in text frames.
6. Wait for `gateway.ready` (has `replay_epoch`, `change_events`, `heartbeat`), then send `client.capabilities {server_requests: true}` (from 0.21.4 the host refuses approvals etc. to clients that did not send it).
7. Client sends `gateway.ping` every 15 s; drop after 45 s of silence; reconnect backoff 1, 2, 4, 8, 16, 30 s.
8. One shared socket per connection across all screens; closed on app background, reopened on foreground.
9. A 401 triggers one silent re-login; a rejected password never resends automatically.

Version gate: refuses hosts older than **Hermes 0.21.3** ("first release with the gateway contract"); tested pin **0.21.5** (`ca6782850432927f33df4775cb6dd45bb51460d2`). `-32601` on a method marks it unavailable for that connection and hides the control.

### 2b. JSON-RPC methods Hermex uses (extracted from `HermesCall.swift` + `Bots/`)
`approval.respond, clarify.lock, client.capabilities, command.dispatch, commands.catalog, complete.path, complete.slash, config.set, connection.respond, file.attach, groups.{approve,capabilities,create,disband,list,log,rename,retry,send,state,stop}, insights.get, llm.oneshot, model.options, profiles.{configure,create,describe,get_asset,list,set_asset}, projects.{create,delete,tree,update}, prompt.{background,btw,submit}, request.answer, session.{active_list,branch,close,compress,control,control.read,create,cwd.set,delete,events.since,interrupt,list,most_recent,redirect,resume,steer,title,undo,workspace.move}, slash.exec, subagent.{interrupt,list,tail}`.

Key events consumed: `message.start/delta/interim/complete`, `reasoning.delta`, `tool.start/complete` (by `tool_id`), `session.info` (running, model, cwd, yolo, usage), `session.title`, `session.usage`, `todo.updated` (plan), `subagent.*`, `request.cancel`, `connection.request/update`, `status.update`, `btw.complete`, `background.complete`, `sessions.changed`. Every event has `seq`; reattach uses `session.resume {omit_messages}` + `session.events.since` (host replay ring of 512 events).

Send modes while busy: Queue = `prompt.submit {queued: true}`, Steer = `session.steer`, Stop & send = `session.redirect`, Stop = `session.interrupt`. Edit/Regenerate/Retry = `prompt.submit` with `truncate_before_row_id`.

### 2c. REST paths used on the dashboard
`/api/status, /auth/password-login, /api/auth/me, /api/auth/ws-ticket, /api/ws, /api/health, /api/config, /api/env, /api/profiles, /api/profiles/active, /api/profiles/{name}, /api/profiles/{name}/soul, /api/sessions (list, ?archived=only), /api/sessions/{id} (GET, PATCH pinned/archived/title/unread), /api/sessions/{id}/messages (transcript pages: ?profile=&order=latest&limit=100&offset=&include_compacted=true), /api/sessions/{id}/export, /api/sessions/import, /api/sessions/search, /api/cron/jobs (+ /{id}, /pause, /resume, /trigger, /runs), /api/cron/delivery-targets, /api/skills, /api/skills/content, /api/skills/toggle, /api/fs/{list,read-text,write-text,download,git-root}, /api/files/mkdir, /api/git/*, /api/chat/image-upload, /api/audio/transcribe, /api/audio/speak, /api/analytics, /api/plugins/kanban(+/events), /api/dashboard/agent-plugins(+/install), /api/dashboard/plugins/hub, /api/gateway/restart, /api/hermes/update(+/check, /receipt), /api/actions/hermes-update/status, /api/plugins/hermex-push/{pairing,restart}`.

Session list default query: `?profile=&order=recent&archived=exclude&limit=100&offset=&min_messages=1&exclude_sources=cron,kanban,oneshot,subagent,tool`.

Attachments: images via `POST /api/chat/image-upload?profile=` (`{filename, data_url}` → `{ok, path}`, then prompt carries path + vision-tool instruction); documents via `file.attach {session_id, name, data_url}` → `@file:` token. Limits 8 files, 25 MB each, 50 MB total.

### 2d. Server requirements (confirmed)
- Hermes Agent ≥ 0.21.3 running `hermes dashboard` (default port 9119).
- `config.yaml`: `dashboard.basic_auth.username`, `dashboard.basic_auth.password_hash`, `dashboard.basic_auth.secret` (≥ 32 random bytes so sign-ins survive restart), `dashboard.public_url` set to the exact phone-facing URL (else `400 Invalid Host header`). The dashboard refuses to serve beyond 127.0.0.1 without sign-in.
- Reachability: Cloudflare Tunnel, Tailscale Serve, NetBird, or same Wi-Fi HTTP (fallback).
- **No companion plugin is needed for Bot Mode.** It uses only stock dashboard + gateway surfaces.
- **Push is the only plugin**: `hermex-push` (hermes-agent platform plugin) + a Cloudflare Worker relay (default `https://hermex-relay.hermex-relay.workers.dev`, self-hostable via `HERMEX_PUSH_RELAY_URL`). The phone provisions it itself: `GET /api/plugins/hermex-push/pairing` (200 paired / 409 needs relay URL / 404 bodies distinguish states), else `PUT /api/env` (relay URL), `POST /api/dashboard/agent-plugins/install {identifier: "https://github.com/uzairansaruzi/hermex-push.git/plugin", force: true, ...}`, `.../hermex-push/enable`, `POST /api/gateway/restart`, then pairing returns `{relay_url, install_key, preview_key, platform, payload_version, plugin_version}`. Previews sealed with AES-256-GCM on the host and opened in a Notification Service Extension. A freshly installed plugin needs a dashboard restart ("Restart Hermes to finish").

Onboarding's Hermes setup prompt, verbatim (from `Features/Onboarding/OnboardingFlowPolicy.swift`), worth copying for Crew:

```
Set up the Hermes dashboard on this machine for access from my iPhone.

Inventory before changing anything:
- Find the running `hermes dashboard` process, its `--host` and `--port` (default 9119), its launcher or service, and its `config.yaml`. Reuse and preserve working state instead of reinstalling it.
- Check who owns the dashboard port with `lsof -nP -iTCP:9119 -sTCP:LISTEN` (or the OS equivalent, with the actual port). Do not kill an unknown process; stop and report the owner or conflict.
- Look for an existing HTTPS route to the dashboard: a Cloudflare Tunnel, Tailscale Serve, or a reverse proxy. Preserve every existing route; do not reset, remove, or overwrite one.

Require sign-in:
- Never run the dashboard without its sign-in gate, and never bypass or disable it.
- Keep an existing `dashboard.basic_auth.username` and password. Otherwise set `dashboard.basic_auth.username` and a `password_hash` for a secure random password, hashed with the dashboard's own Python from the hermes-agent checkout: `python -c "from plugins.dashboard_auth.basic import hash_password; print(hash_password('<password>'))"`. Do not store a plaintext `password`.
- Keep an existing `dashboard.basic_auth.secret`. Otherwise set it to a random value of at least 32 bytes (for example `openssl rand -base64 32`) so sign-ins survive a restart.
- Edit only these keys and `dashboard.public_url` in `config.yaml`, and preserve every other line. Do not print `config.yaml` or the secret.

Choose the address my iPhone will use:
- Prefer HTTPS: an existing Cloudflare Tunnel or private network (such as Tailscale) route to the dashboard, with the dashboard still bound to `127.0.0.1`. If none exists, propose the exact steps to add one and wait for me to approve them.
- Treat same Wi-Fi over plain HTTP as an explicit manual fallback only. Explain that the password then crosses the network unencrypted, and require my confirmation before binding beyond loopback.
- Set `dashboard.public_url` to the exact address my iPhone will use, scheme and host (for example `https://hermes.example.com`). Without it the dashboard rejects the phone with `400 Invalid Host header`.
- Restart only the dashboard, through its existing launcher or service, and tell me before you do. Do not configure auto-start yourself; propose the exact OS-appropriate commands and wait for me to run them.

Verify in this order:
1. Confirm the dashboard locally with `curl --fail http://127.0.0.1:9119/api/status` (use the actual port).
2. Confirm the phone's address with `curl --fail <exact-phone-address>/api/status`, keeping its scheme and port (`https://` unless I confirmed the same Wi-Fi fallback), and check that it reports `"auth_required": true` with `basic` in `auth_providers`.

Reply with the exact address, username, password, and both check results, plus any remaining action required on my iPhone. Do not include `config.yaml` or the secret.
```

## 3. Chat UX details (confirmed from CHANGELOG, Localizable.xcstrings, source)
- **Worked-for accordion**: since 1.6 settled tool calls, live tool activity and thinking render as compact log rows; a finished turn folds behind one "Worked for <elapsed>" row (setting **Fold Finished Turns**); a "Working for <elapsed>" counter / working pill sits at the transcript tail (counts from the host's `turn_started_at`). Long tool lists show "+N previous tool calls" / "Show fewer tool calls"; expanded rows are capped in a scrollable window; new rows fade in. Bot turns fold the same way (1.8).
- **Thinking/tool settings**: "Thinking and Tool Cards" (show/hide), "Expand Thinking by Default", tool cards start expanded option, "Fast" and effort chips in composer. Reasoning summary formatter shows a one-line "Thinking, <summary>".
- **Streaming toggles**: "Pulse While Streaming" (light haptic tick as each reply streams), "Haptic Feedback", opt-in response speed metrics, Message Timestamps, code line wrapping, hide attachment paths, RTL layout, start reading completed response from its beginning, dismiss keyboard after sending.
- **Send while running**: default `StreamingSendBehavior` = Steer / Stop and send / Queue; long-press Send overrides per message (1.8). Queue shows a receipt; Steer hints appear inline in the transcript.
- **Show more for long user messages**: `UserBubbleFoldPolicy`: folds when the bubble wraps past 8 lines, showing 6 lines with Show more / Show less.
- **Markdown**: MarkdownUI + swift-cmark, Highlightr/Splash code highlighting (off main thread), SwiftMath for LaTeX (inline and display), tables with clear edges, diff/patch code blocks coloured, inline images with lightbox, link previews, in-app Safari sheet, file links open in source viewer. Streaming renderer with a reveal gate.
- **Interrupting**: Stop = `session.interrupt`, confirmation only when a queued prompt or open request would be lost. Run-status pill shows "Waiting for you" when a request is open.
- **Requests**: approval overlay and clarification card pinned above the composer; plan strip (`todo.updated`) pinned above composer while running; `/btw` side-question panel; `/background` cards; delegated-work (subagents) toolbar button with a sheet.
- **Message actions**: copy, timestamps, select text and "ask Hermex about the selection", Edit, Regenerate, Fork From Here, Listen.
- **Failed turns**: outcome row with reason, "Limit resets at …", Retry.
- **Context**: context window indicator from `session.usage`; `/compress` card.
- **Composer**: Liquid Glass pill, toolbar row when focused, `@path` file chips, `/` slash + skill autocomplete with skill chips, model+effort control.

## 4. Grok Bot (secondary inspiration)

Confirmed from xAI docs:
- A bot = named teammate with role/description, own memory and conversation, running on a **persistent cloud Linux computer** (browser, filesystem, terminal) shared by all your bots; each bot gets its own screen on it. Platforms: macOS, Windows, Linux desktop; iPhone, iPad, Android.
- Home: `+` → New Bot / New Group Chat; pin or hide conversations; search across Messages / Bots / Group Chats / Files / Routines / All.
- Chat: text, dictation, voice chat, attachments, threads, reactions, `@bot` / `@everyone` in groups, per-conversation drafts, share sheet, action cards ("New Email" / "New Slack Message" with Send / Discard).
- **Screen view**: open the computer from a conversation to watch the bot work; take over for passwords/2FA/CAPTCHA, then "I'm done".
- **Routines**: walk a bot through a task once, saved as a skill/routine; per-bot list in the bot's profile with schedule, next run, instruction, Run history, Active toggle. Editing/testing only on desktop. Bot timezone setting.
- Desktop sidebar: attention states ("Needs attention", unread, working/typing), dock badge, "Connect apps" (plugins) and "Your plugins". Per-bot settings: name, label, description, avatar, notifications toggle. Auto Review approval rules.
- Third-party only (unverified): the desktop window is three panes, bots/channels left, conversation centre, the bot's Linux box and routines on the right (search summary of a third-party wiki and a how-to guide). The official docs do not describe the right panel. The term "favourites" does not appear; pinning is the documented equivalent.

### Mapping Grok ideas onto Hermes capabilities
| Grok idea | Hermes equivalent | Notes |
| --- | --- | --- |
| Bot list with pinned at top | `profiles.list` + `ui_meta["hermes-bots"].pinned` | Exactly what Hermex does (tiles above the list). |
| Bot avatar/name/label | `ui_meta` title/description/shape/color + `profiles.set_asset` photo | Shared with Desktop. |
| Routines per bot | Hermes cron. Desktop's built-in `hermes-bots` plugin has a **Routines pane** backed by `cron.manage {action: "list", profile}` RPC, jobs namespaced `[bot:<name>] <routine>`, runs landing in the bot's chat (`apps/desktop/src/plugins/hermes-bots/cron.tsx`). | **Hermex has no per-bot routines**: cron is a global "Tasks" screen (`GET /api/cron/jobs`, all profiles). Per-bot Routines is an open gap Crew could fill. |
| Bot's screen panel | `terminal.read`, `window.read`, `preview.read/act` server requests exist but need Desktop renderer data; no remote screen stream. | Closest Hermes analogue for a right panel: live tool activity, plan (`todo.updated`), subagents, files/git for the session's cwd. **[inference]** |
| Needs attention / working states | `session.active_list` (`waiting`, `working`, `streaming`) | Hermex polls every 5 s while busy. |
| Group chats | `groups.*` hosted rooms | 2 to 6 bots. |
| Approvals / Auto Review | `approval` server requests with once/session/always/deny; `yolo` per session | |
| Plugins / connect apps | `connection.request/update` + `connection.respond`, `/api/dashboard/agent-plugins` | |
| Notifications per bot | hermex-push plugin pattern | Would need Crew's own plugin/relay or reuse hermex-push. **[inference]** |
| Bot-to-bot messaging | `message_agent` tool via Desktop's mention note | Delivered on next run, not interrupt. |

## 5. Gaps in what I could find
- No Reddit or Hacker News threads about Hermex surfaced. X (@uzairansar) and the Hermex Discord are login-walled and were not checked.
- TestFlight notes are not public; TESTFLIGHT.md is maintainer process only. Members get early builds via Buy Me a Coffee.
- App Store screenshots have no captions; the website's captions cover only webui-era screens and don't mention Bots.
- Third-party coverage (scriptbyai, lumadock, tonyreviewsthings) repeats the README and adds nothing on Bot Mode.
