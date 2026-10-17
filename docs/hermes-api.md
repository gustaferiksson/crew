# Hermes Agent dashboard API: spec for a native SwiftUI client

Research date 2026-10-13. Read-only; no config touched, no authenticated or mutating request sent anywhere.

## 0. Versions and sources

| Thing | Version |
|---|---|
| The test server (live, from public `GET /api/health` + `/api/status`) | **0.21.7**, release_date 2026.9.24, commit `71d34bad10` = git tag `v0.21.7` |
| Local install `~/.hermes/hermes-agent` (git checkout, `~/.local/bin/hermes` -> `.hermes/bin/hermes`) | `0.21.7+302.gae3f9f9` (main, 302 commits past v0.21.7) |
| Hermex (uzairansaruzi/hermex, MIT) `HERMES_AGENT_TESTED_SHA` | tested against 0.21.5 / `ca67828504` |

All file:line refs below are against the **v0.21.7** tag (exported to `scratchpad/src/` via `git archive v0.21.7`), i.e. exactly what the server runs. `git diff v0.21.7 HEAD` shows no changes in `hermes_cli/web_routers/`, `hermes_cli/dashboard_auth/`, `web_server_chat.py`, `tui_gateway/ws.py`, `tui_gateway/contracts/` (except `connectors_operation.py`), so local HEAD line numbers match too for those.

The authoritative wire contract for chat is generated from Python: `tui_gateway/contracts/*.py` -> `apps/shared/src/gateway-contract.generated.ts` (218 KB) and `apps/shared/src/gateway-contract.openrpc.json` (1 MB OpenRPC doc). **Use the OpenRPC JSON to generate Swift Codable types** rather than hand-writing them.

## 1. Architecture in one paragraph

`hermes dashboard` runs a FastAPI/uvicorn app (`hermes_cli/web_server.py`, default port **9119**, `hermes_cli/main_dashboard.py:57`, `web_server.py:1593`). It serves: (a) the React SPA, (b) a REST API under `/api/*` (config, profiles, sessions list/history, skills, toolsets, MCP, cron, files, audio...), (c) auth routes under `/auth/*`, and (d) **WebSocket `/api/ws`**: a JSON-RPC 2.0 sidecar that drives `tui_gateway` (the same backend the Ink TUI and Hermes Desktop use). **All live chat (create session, send prompt, streaming, tool events, approvals, interrupt) goes through `/api/ws`. There is no SSE and no REST "send message" endpoint on the dashboard.** REST is for listing/reading/editing. Hermex's "Hermes server" mode uses exactly this split.

(Separately the gateway runs an OpenAI-compatible `api_server` platform on `127.0.0.1:8642` (`/v1/chat/completions`, `/v1/runs`, needs `API_SERVER_KEY`, `gateway/platforms/api_server.py:1-6`). It is not exposed on the test server and is out of scope.)

---

## 2. Serving, base URL and authentication

### 2.1 What the test server presents (unauthenticated GETs only)

```
GET /                    -> 302 location: /login?next=%2F        server: uvicorn
GET /login               -> 200 text/html "Sign in — Hermes Agent"
GET /api/auth/providers  -> 200 {"providers":[{"name":"basic","display_name":"Username & Password","supports_password":true}]}
GET /api/health          -> 200 {"ok":true,"version":"0.21.7","displayVersion":"0.21.7","commit":"71d34bad...","auth_required":true}
GET /api/status          -> 200 {... "auth_required":true,"auth_providers":["basic"],"auth_flows":["cookie","native_pkce"],
                                 "install_id":"f990dea4...","profiles":["default"],"gateway_running":true,
                                 "active_sessions":0,"gateway_mode":"single","version":"0.21.7", ...}
```

**Reverse proxy:** responses are HTTP/2 with `server: uvicorn` (uvicorn does not speak h2, so a TLS-terminating proxy is in front), but it is **transparent**: no `WWW-Authenticate`, no `cf-*` headers, no redirect to an external IdP, no basic-auth challenge. The only gate is the **dashboard's own auth gate with the `basic` provider** (`plugins/dashboard_auth/basic/__init__.py`). Dashboard is mounted at the root (no `X-Forwarded-Prefix` sub-path). A native client therefore needs no proxy headers today, but should support optional custom headers (Hermex does, for Cloudflare Access service tokens: `CF-Access-Client-Id/Secret`), and must **never** send its own `Authorization: Bearer` for a proxy, because Hermes reads Bearer as its own credential.

### 2.2 When the gate engages
- `should_require_auth`: any non-loopback bind, or a non-loopback `dashboard.public_url` (`web_server.py:522-547`). `--insecure` is ignored since June 2026.
- Host header must match bound host, `dashboard.public_url` host, or bind is `0.0.0.0` (`web_server.py:602-627`, middleware `:630`). Wrong Host -> 400.
- Public `/api` paths (no auth): `/api/health`, `/api/status`, `/api/config/defaults`, `/api/config/schema`, `/api/model/info`, `/api/dashboard/themes`, `/api/dashboard/plugins`, `/api/cron/fire` (`dashboard_auth/public_paths.py:9-29`). Plus `/auth/*`, `/login`, `/api/auth/providers` (`dashboard_auth/middleware.py:39-43`).
- **CORS** allows only `http(s)://localhost|127.0.0.1(:port)` (`web_server.py:809-814`). Irrelevant for a native URLSession client (no Origin preflight). WS Origin: if absent, accepted; if present must match host (`web_server_chat.py:167-199`).
- The legacy `X-Hermes-Session-Token` / `_SESSION_TOKEN` (`web_server.py:386-387, 457-468`) is loopback-only and is **rejected** in gated mode. Do not use it.

Basic provider token lifetimes: access 12 h (`dashboard.basic_auth.session_ttl_seconds`), refresh 30 d, stateless HMAC tokens (`basic/__init__.py:30-34`). If `dashboard.basic_auth.secret` is unset, sessions die on server restart.

### 2.3 Login option A (what Hermex does, recommended): password -> cookies -> WS ticket

Routes: `dashboard_auth/routes.py`.

1. `GET /api/status` (public). Check `auth_required == true`, `"basic" in auth_providers`, record `version` and `install_id` (Hermex pins `install_id` as trust-on-first-use).
2. `POST /auth/password-login` (`routes.py:447-493`)
   ```json
   {"provider":"basic","username":"…","password":"…","next":""}
   ```
   -> `200 {"ok":true,"next":"/"}` and `Set-Cookie`: `hermes_session_at`, `hermes_session_rt`, `hermes_session_provider` (HttpOnly, SameSite=Lax, Secure on https; `cookies.py:27-31, 60-71`). Errors: 401 bad creds, 404 unknown provider, 429 rate limited (10/min/IP, `routes.py:357-359`), 503 provider down.
   Use a dedicated `HTTPCookieStorage` per server; share it with the `URLSessionWebSocketTask`.
3. `GET /api/auth/me` (`routes.py:524-553`) -> `{"user_id","email","display_name","org_id","provider":"basic","expires_at"}`. Verify `provider == "basic"`.
4. Every REST call just carries the cookies. When the access token lapses, the middleware **transparently refreshes** with the RT cookie and re-sets cookies on that response (`middleware.py:184-209`). On final failure: `401 {"error":"session_expired"|"unauthenticated","detail":"Unauthorized","reason":"…","login_url":"/login?next=…"}` (`middleware.py:72-87`) -> re-run step 2. 503 = provider unreachable, keep cookies.
5. WebSocket: `POST /api/auth/ws-ticket` (body `{}`) -> `{"ticket":"…","ttl_seconds":30}` (`routes.py:556-568`, `ws_tickets.py:21`). Single use, 30 s. Then open
   ```
   wss://hermes.example.com/api/ws
   Sec-WebSocket-Protocol: hermes-gateway-v1, hermes-gateway-ticket.<ticket>
   ```
   (preferred: keeps the ticket out of URLs/logs; server selects `hermes-gateway-v1`, `web_server_chat.py:207-222`) or `wss://…/api/ws?ticket=<ticket>`. Mint a fresh ticket for **every** (re)connect. Hermex: `HermesREST.swift:608-616`, `maximumMessageSize = 16 MiB`.
6. Logout: `POST /auth/logout` (clears cookies; basic has nothing to revoke).

WS close codes on auth failure: 4401 bad credential, 4403 host/origin mismatch, 4404 chat disabled, 4408 peer not allowed (`web_routers/chat_ws.py:120-140`).

### 2.4 Login option B: RFC 8252 native PKCE -> bearer tokens (`auth_flows` includes `native_pkce`)

Gives `access_token`/`refresh_token` in JSON (Keychain-friendly, no cookie jar). Designed for Hermes Desktop.

1. `GET /auth/native/authorize?code_challenge=<S256>&code_challenge_method=S256&redirect_uri=http://127.0.0.1:<port>/cb&state=<s>[&provider=basic]` (`routes.py:289-335`). `redirect_uri` **must** be an `http://127.0.0.1` or `[::1]` loopback literal (`routes.py:237-273`); `localhost`, custom schemes and https are rejected. For a password provider it 302s to `/login` and sets a `hermes_session_pkce` cookie containing an opaque broker handle.
2. `POST /auth/password-login {provider:"basic",username,password}` **with that PKCE cookie** -> `{"ok":true,"next":"http://127.0.0.1:<port>/cb?code=<gw_code>&state=<s>"}` and no session cookies (`routes.py:470-493`). The client does not need to actually listen on the port: it can parse `code` from `next` directly when it performs this POST itself with URLSession.
3. `POST /auth/native/token {"code":"…","code_verifier":"…"}` (`routes.py:574-591`) ->
   ```json
   {"access_token":"…","refresh_token":"…","token_type":"Bearer","expires_at":1791900000,"provider":"basic","user_id":"admin"}
   ```
   Code TTL 120 s, pending TTL 600 s, single use (`native_flow.py:29-31`).
4. REST: `Authorization: Bearer <access_token>` (`middleware.py:173-182`). WS: `wss://…/api/ws?token=<access_token>` (verified via the same provider, `web_server_chat.py:320-370`), or still use ws-ticket (ticket endpoint accepts the bearer session).
5. Refresh: `POST /auth/native/refresh {"refresh_token":"…","provider":"basic"}` -> same payload; `401 {"error":"session_expired"}` -> re-login (`routes.py:594-617`).

Option B is cleaner for a SwiftUI app (no cookie jar, token in Keychain) and is fully doable with URLSession alone (steps 1-3 without a browser, since basic is a password provider). Caveat: the `?token=` WS leg is new in the 0.21.x line; Hermex (tested on 0.21.5) uses option A, which is the proven path.

---

## 3. Profiles ("personas"/"bots"), identity, prompt, model, skills, toolsets, MCP, appearance

Profiles are directories (`~/.hermes` = `default`, `~/.hermes/profiles/<name>`), each with its own `config.yaml`, `SOUL.md`, `profile.yaml`, skills, `state.db`. Almost every REST route takes **`?profile=<name>`** (or `profile` in the JSON body) to scope reads/writes; WS RPCs take a `profile` param. The test server had only `default`.

### 3.1 Listing

**RPC (richest, what Desktop/Hermex use):** `profiles.list {include_sessions?: bool, profile?}` (`contracts/profiles_vault_complete_foreign_subagents.py:150-185`)
```json
{"profiles":[{"name":"default","path":"/home/…/.hermes","is_default":true,"model":"…","provider":"…",
  "description":"","display_name":"","skill_count":42,"previous_names":[],
  "last_session":{…},"worker_session":{…},
  "canonical_session":{"id":"…","resolved_id":"…","title":"Bot Chat","preview":"…","last_active":1791880000,"message_count":12},
  "ui_meta_revisions":{"hermes-bots":3},
  "ui_meta":{"hermes-bots":{"title":"Ada","shape":"blob","color":"#8b5cf6","custom":true,"expression":"happy","pinned":true}},
  "has_avatar":false}],
 "bot_mode_protocol":true,"install_id":"f990dea4…"}
```
**REST:** `GET /api/profiles` -> `{"profiles":[{name,path,is_default,model,provider,has_env,skill_count,gateway_running,description,description_auto,display_name,bot_title,distribution_*,has_alias}]}` (`web_routers/profiles.py:84-100, 806`). `GET /api/profiles/active` -> `{"active","current"}`.

### 3.2 Editing

| Field | REST | RPC |
|---|---|---|
| Display name | `PATCH /api/profiles/{name}` `{"new_name"}` (for `default` it only sets presentation `display_name`; for others it **renames the directory**) `profiles.py:959` | Bot title lives in `ui_meta["hermes-bots"].title` via `profiles.configure` |
| Description | `PUT /api/profiles/{name}/description` `{"description"}` -> `{ok,description,description_auto:false}` `profiles.py:1036` | `profiles.configure {name, description}` |
| SOUL (persona/identity prompt) | `GET /api/profiles/{name}/soul` -> `{"content","exists"}`; `PUT` `{"content"}` `profiles.py:999-1033` | `profiles.describe` returns `soul`; `profiles.configure {soul}` |
| Instructions overlay | `agent.system_prompt` (user-owned manual overlay) and `display.personality` (named overlay) in config.yaml (`hermes_cli/personality.py:1-7`): `GET /api/config?profile=` / `PUT /api/config?profile=` `{"config":{"agent":{"system_prompt":"…"}}}` (deep-merged, `config_env.py:80-125`) | `config.set {key:"personality", value, session_id?}` |
| Model | `PUT /api/profiles/{name}/model` `{"provider","model"}` `profiles.py:1050`; or `POST /api/model/set?profile=` `{"scope":"main","provider","model","reasoning_effort?","confirm_expensive_model?"}` (may answer `{ok:false,confirm_required:true,confirm_message}`) `models.py:376` | `profiles.configure {model,provider,confirm_expensive_model}`; live session switch: `config.set {key:"model", value:"provider/model" or model, session_id}` |
| Available models | `GET /api/model/options?profile=&refresh=` -> `{"providers":[{slug,name,models[],is_current,authenticated,capabilities{},pricing{},…}],"model","provider"}` `models.py:138`; `GET /api/model/info?profile=` (public) | `model.options` (same shape, `contracts/config_free_tier_control.py:536-571`) |
| Skills | `GET /api/skills?profile=` -> `[{name,description,category,…,enabled,usage,provenance:"hub"|"bundled"|"external"|"agent"}]`; `PUT /api/skills/toggle {name,enabled,profile}`; `GET/PUT /api/skills/content`; `POST /api/skills` `skills.py:343-444` | `profiles.configure {disabled_skills:[…]}` |
| Toolsets | `GET /api/tools/toolsets?profile=` -> `[{name,label,description,platform,platform_label,enabled,available,configured,tools[]}]`; `PUT /api/tools/toolsets/{name} {enabled,profile}` `tools.py:230-345` | `profiles.configure {enabled_toolsets:[…]}`; `toolsets.list`, `tools.list` |
| MCP servers | `GET /api/mcp/servers?profile=` -> `{"servers":[…]}`; `POST` `{name,url|command,args,env,auth,bearer_token}`; `PUT` (replace map); `DELETE /api/mcp/servers/{name}`; `PUT /api/mcp/servers/{name}/enabled`; `POST …/test` `mcp.py:94-372` | `profiles.configure {enabled_mcp_servers:[…]}`; `mcp.servers.*` |
| Create / delete | `POST /api/profiles {name,clone_from?,description?,provider?,model?,…}`; `DELETE /api/profiles/{name}` | `profiles.create` |

`profiles.describe {name}` -> `{name,description,soul,model:{provider,default},skills:[{name,enabled}],toolsets:[{name,label,description,tool_count,enabled}],toolsets_pinned,mcp_servers:[{name,transport,enabled}]}` (`contracts/…subagents.py:228-266`): one call for a whole editor screen.

`profiles.configure {name, ui_meta?, ui_meta_expected_revisions?, soul?, description?, model?, provider?, confirm_expensive_model?, disabled_skills?, enabled_toolsets?, enabled_mcp_servers?}` -> `{ok, applied:{ui_meta,ui_meta_revisions,ui_meta_conflicts,soul,description,model,skills,toolsets,mcp_servers}, confirm_required?, confirm_message?}` (`:269-314`). Sections are independent; only sent sections are applied.

### 3.3 Appearance / avatar: **server-side**

Stored in the profile's `profile.yaml` under `ui_meta`, namespaced by client plugin id. Hermes Desktop and Hermex share the namespace **`ui_meta["hermes-bots"]`** (`tui_gateway/methods_profiles.py:256-278, 593-645`; 64 KB cap; rides every `profiles.list`).

- Write: `profiles.configure {name, ui_meta:{"hermes-bots":{…whole object…}}, ui_meta_expected_revisions:{"hermes-bots":<rev>}}`. Per-key compare-and-swap; on conflict `applied.ui_meta_conflicts` comes back, re-read and retry (Desktop retries 3x). Send the received object back whole with your changes merged so other clients' keys survive. `null` value deletes a key.
- Any namespace key is accepted and versioned on its own: Crew keeps its read marker in `ui_meta["crew"] = {session, messages}` (revision `ui_meta_revisions["crew"]`); writing it leaves `hermes-bots` and its revision untouched, and the float round-trips exactly (verified on `crew-test`).
- Keys (Desktop `apps/desktop/src/plugins/hermes-bots/types.ts:64-95` + Hermex `BotProfileAppearance.swift`): `title`, `description`, `shape`, `color` (hex), `custom` (bool), `imageKind` (`"photo"|"shape"`), `expression` (Hermex-owned; Desktop preserves it), `role` (Crew-owned work title, `docs/flows/bot-roles.md`; Desktop preserves it), `pinned`, `hidden`, `sectionId`, `sectionName`, `groups`, `created` (ms). Never store data URLs here; legacy `chat` key is dead.
- Hermex enums: shape `circle, blob, squircle, pill, triangle, hexagon, cloud, drop`; expression `neutral, attentive, surprised, excited, happy, laughing, angry, sad, scared, wary, confused, curious, proud, shy, bored, sleepy` (eye geometry from jeremy-prt/bloub, MIT); colour palette `#ffffff` (adaptive "Auto": white on dark, black on light), `#a9703d #ef4444 #f97316 #f59e0b #22c55e #14b8a6 #38bdf8 #8b5cf6 #ec4899 #8e8e93`.
- Avatar image: `profiles.set_asset {name, asset:"avatar", data:"data:image/png;base64,…"}` (PNG/JPEG/WebP sniffed, max 2 MB) or `{…, clear:true}` -> `{ok,asset,size,removed?}`; `profiles.get_asset {name, asset:"avatar"}` -> `{found,mime,size,data(data URL)}` (`methods_profiles.py:411-470`). Rows carry `has_avatar` so you only fetch when needed. Stored as `<profile>/assets/avatar.<ext>`.

### 3.4 Bot-chat convention (Desktop + Hermex)
One canonical "forever chat" per profile = the stored session **titled exactly `Bot Chat`**, created hidden. Resolve every time via `session.list {profile, title:"Bot Chat", include_hidden:true}`; `profiles.list` also reports it as `canonical_session` (`resolved_id` = live compression tip). No stored session-id pointer (`apps/desktop/src/AGENTS.md:65-99`). Side chats are ordinary visible sessions.

---

## 4. Chat over `/api/ws` (JSON-RPC 2.0)

### 4.1 Framing and handshake (`tui_gateway/ws.py`)
- One JSON object per WS **text** frame (newline-delimited JSON-RPC, same as stdio).
- Server's first frame (`ws.py:364-371`):
  ```json
  {"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready","payload":{"skin":{…},"change_events":true,"heartbeat":true,"replay_epoch":"…"}}}
  ```
  Store `replay_epoch`; if it changes on reconnect the backend restarted, so reset seq watermarks.
- Client must then send `client.capabilities {"server_requests":true}` (`contracts/liveness.py:30-47`). Without it, approvals/clarify/sudo/secret requests fail fast server-side.
- Keepalive: send `{"jsonrpc":"2.0","id":N,"method":"gateway.ping"}` about every 15 s; answered `{"result":{"ok":true}}` even mid-turn (`ws.py:420-424`). Server send deadline is 30 s; shared client treats 45 s silence as dead (`ws.py:60-69`). `ping` RPC also exists.
- Requests: `{"jsonrpc":"2.0","id":<int>,"method":"…","params":{…}}`; replies `{"result":…,"id"}` or `{"error":{"code","message"},"id"}`. Unknown param keys are rejected (code 4000), unknown method -32601.
- Events (`tui_gateway/server.py:700-704`, seq stamped in `event_replay.py:67-87`):
  ```json
  {"jsonrpc":"2.0","method":"event","params":{"type":"message.delta","session_id":"<runtime id>","seq":42,"payload":{"text":"Hel"}}}
  ```
- Server->client requests (`server_requests.py:1-30, 82-84`): `{"jsonrpc":"2.0","id":"srq-1a2b3c4d5e6f","method":"approval","params":{"session_id":"…",…}}`. Answer with a normal JSON-RPC response on the **same id**. A withdrawn one arrives as event `request.cancel {id,method,reason}`.
- On disconnect the server detaches your sessions to a grace-window reaper; reattach with `session.resume`/`session.activate` and call `session.events.since {session_id, last_seen:<seq>}` -> `{events[], latest_seq, truncated, count, epoch, open_requests[]}` (`contracts/sessions.py:719-737`). `truncated:true` means refetch full state.

### 4.2 Session lifecycle (`contracts/sessions.py`)
**Two ids:** a *runtime* `session_id` (what every live RPC and every event uses) and a *stored* id (`stored_session_id`, the `state.db` key used by REST and `session.list`). Mixing them up is the easiest client bug.

- `session.create {profile?, title?, model?, provider?, reasoning_effort?, cwd?, messages?(seed), hidden?, close_on_disconnect?, idempotency_key?}` -> `{session_id, stored_session_id, message_count, messages[], info:SessionLiveInfo}` (`:110-152`). The DB row appears on the first prompt.
- `session.resume {session_id:<stored id or exact title>, profile?, lazy?, omit_messages?, inline_images?:false recommended on mobile}` -> `LiveSessionSnapshot {session_id(runtime), stored_session_id, messages[], info, running, status:"idle|starting|waiting|working|streaming|resuming", inflight{assistant,user,streaming,…}, queued, pending_approval, open_requests[], todo_state, turn_started_at}` (`:62-90, 188-203`). `session.activate` attaches to an already-live one.
- `session.list {profile?, title?, limit?, include_hidden?}` -> `{sessions:[{id,title,preview,started_at,message_count,live_message_count,source,_lineage_root_id}]}` (`:226-250`). `session.active_list` = live runtimes with `status` + `session_key` (Hermex uses it for working/waiting badges).
- `session.history {session_id}` -> `{count, messages:[TranscriptMessage]}` (`:488-500`).
- `session.title`, `session.delete`, `session.archive`, `session.set_hidden`, `session.branch`, `session.undo`, `session.compress`, `session.usage`, `session.close {session_id}` -> `{closed}`.

`SessionLiveInfo` (`contracts/common.py:78-118`): `model, provider, reasoning_effort, fast, yolo, approval_mode, tools{toolset:[names]}, skills{…}, cwd, branch, project, personality, running, turn_started_at, title, stored_session_id, version, usage, profile_name, mcp_servers[{name,status,tool_count,error}], system_prompt(resolved), credential_warning`. Also pushed live as event `session.info`.

### 4.3 Sending a message
`prompt.submit {session_id, text, profile?}` (`contracts/prompt_voice.py:26-79`) -> `{status:"streaming"|"queued"|"steered"|"redirected", user_row_id?}`. A busy session queues/steers rather than refusing. Edit/regenerate uses `truncate_before_row_id` + `confirm_truncate:true`.

Attachments (queued for the next `prompt.submit`):
- `image.attach_bytes {session_id, content_base64, filename?}` -> `{attached,path,count,width,height,token_estimate}` (`:113-133`).
- `pdf.attach {session_id, content_base64, filename, first_page?, last_page?}` (renders pages to images).
- `file.attach {session_id, data_url, name}` -> `{attached,name,path,ref_path,ref_text,uploaded}`; include `ref_text` (an `@file:` ref) in the prompt (`:168-185`).
- REST alternative: `POST /api/chat/image-upload?profile= {"data_url","filename"}` -> `{ok,path,name,bytes,mime_type}` (`web_routers/files.py:470-504`), then `image.attach {session_id, path}`. Also `POST /api/files/upload`.

### 4.4 Stream events for a turn (`contracts/events.py`)
| Event | Payload | Notes |
|---|---|---|
| `message.start` | none | turn began (`:113`) |
| `message.delta` | `{text, rendered?}` | answer tokens, coalesced ~33 ms (`ws.py:83-85`) |
| `reasoning.delta` | `{text, verbose?}` | thinking tokens; only if `display.show_reasoning` (default true) (`agent_callbacks.py:135-138`, `server.py:1952-1954`) |
| `reasoning.available` | `{text}` | whole reasoning block from non-streaming providers |
| `thinking.delta` | `{text}` | TUI spinner face ("(°ロ°) mulling..."), then `""` to clear; not reasoning (verified on 0.21.7) |
| `message.interim` | `{text, already_streamed}` | commentary between tool calls sealed as its own segment |
| `tool.generating` | `{name}` | model is emitting tool args |
| `tool.start` | `{tool_id, name, args?, args_text?, context?, preview?, labels?}` | `:263-280` |
| `tool.complete` | `{tool_id, name, args?, duration_s?, result, summary?, result_text?, inline_diff?, todos?, revision?, labels?}` | `:283-299`; emitter `tool_progress.py:324-366` |
| `tool.output_risk` | `{tool_id,name,risk,findings[],redacted}` | |
| `todo.updated` | `{todos[], revision}` | |
| `status.update` | `{kind, text}` | kinds: status, lifecycle, compacting, goal, … |
| `session.usage` | `{usage}` | mid-turn ticks |
| `session.title` | `{session_id(runtime), title}` | auto-title; on a runtime with no row yet it writes the row (born hidden when created hidden) |
| `message.complete` | `{text, usage, status:"complete"|"error"|"interrupted", reasoning?, error?, failure_reason?, recoverable?, error_surface?, partial?, persisted_turn{row_ids,complete,user_row_id,final_assistant_row_id}}` | `:166-213` |
| `error` | `{message}` | session-level failure outside a turn |
| `notification.show` / `.clear` | `{text,level,kind,ttl_ms,key,id}` | toasts |
| `sessions.changed`, `cron.changed`, `platforms.changed` | `{}` | refetch signals |

**Tool success/error:** there is **no** status field on `tool.complete`. `result` is the parsed JSON of the tool's return string (or the raw string). Desktop infers failure heuristically (`apps/desktop/src/lib/tool-result-summary.ts:372-381`): error if `result.success === false`, `result.ok === false`, `result.status` matches `error|failed|failure|fatal|exception`, or a meaningful `error`/`errors`/`failure`/`exception` key. A started tool with no `tool.complete` before `message.complete{status:"interrupted"}` = cancelled.

**Gating:** `tool.*` events are emitted when the session's `tool_progress_mode != "off"` (default `"all"`; `"verbose"` adds `result_text`) (`server.py:2128-2156`); card tools (edit_file, patch, write_file, clarify, delegate_task, …) always emit. These are server/session config, not client toggles.

**Timing:** `tool.complete.duration_s`; `SessionLiveInfo.turn_started_at` / snapshot `turn_started_at`; `Usage` has `input, output, reasoning, total, calls, context_used/max/percent, cache_hit_pct, avg_latency_s, avg_tps, cost_usd` (`common.py:19-45`); history rows carry `timestamp` (unix seconds).

Example turn:
```
→ {"jsonrpc":"2.0","id":7,"method":"prompt.submit","params":{"session_id":"rt_ab12","text":"What's the weather?"}}
← {"jsonrpc":"2.0","result":{"status":"streaming","user_row_id":1031},"id":7}
← event message.start
← event reasoning.delta {"text":"User wants weather; call web_search."}
← event tool.generating {"name":"web_search"}
← event tool.start {"tool_id":"call_1","name":"web_search","args":{"query":"weather Stockholm"},"context":"weather Stockholm"}
← event tool.complete {"tool_id":"call_1","name":"web_search","args":{…},"duration_s":1.42,"result":{"success":true,"results":[…]},"summary":"Found 5 results in 1.4s"}
← event message.delta {"text":"It's 9°C"} …
← event message.complete {"text":"It's 9°C and cloudy.","status":"complete","usage":{"model":"…","input":2310,"output":45,"total":2355,"calls":2,…},"persisted_turn":{…}}
```

### 4.5 Interrupt, steer, approvals, questions
- Stop: `session.interrupt {session_id}` -> `{status:"interrupted"|"not_interrupted"}` (`contracts/sessions.py:603-620`); the turn ends with `message.complete{status:"interrupted"}`.
- `session.steer {session_id, text}` injects text into the next tool result without stopping; `session.redirect` redirects the active turn.
- Server->client `approval` params `{request_id, command, description, choices:["once","session","always","deny"], allow_permanent, allow_session, tool_name}` -> respond `{"choice":"once"}` (`contracts/server_requests.py:100-130`). Also `clarify` (`{questions:[{id,question,choices?}]}` -> `{answers:{<qid>:"…"}}`, no answers = cancel), `sudo`/`secret` (-> `{value}`), `setup_choose`. Reply -32601 for kinds you don't render.

### 4.6 History retrieval
- **RPC** (`session.resume`/`session.history`): `TranscriptMessage {role, text, timestamp, row_id, display_kind, display_metadata, reasoning, …}`; tool rows are `{role:"tool", name, context, args, tool_call_id, labels}` with **no result content** except for write_file/patch/skill_manage (`tui_gateway/session_history.py:285-360`). Use `inline_images:false` on mobile.
- **REST** (richer, what Hermex uses for transcripts): `GET /api/sessions/{stored_id}/messages?profile=&order=latest&limit=≤500&offset=&include_compacted=true&inline_images=false` (`web_routers/sessions.py:723-782`) ->
  ```json
  {"session_id":"…","profile":"default","messages":[…raw rows…],"pagination":{"limit":100,"offset":0,"order":"latest","returned":100}}
  ```
  Rows mirror the `messages` table (`hermes_state_common.py:449-474` @v0.21.7): `id, role, content, tool_call_id, tool_calls (OpenAI shape [{id,function:{name,arguments}}]), tool_name, timestamp, token_count, finish_reason, reasoning, reasoning_content, display_kind, display_metadata, …`, with compaction summaries projected to `display_content`. Tool results are the `role:"tool"` rows' `content`, joined by `tool_call_id`. Includes compression ancestors.
- `GET /api/sessions?profile=&order=recent&limit=&offset=&archived=exclude|only|include&min_messages=1&exclude_sources=cron,kanban,oneshot,subagent,tool` -> `{sessions:[StoredSessionRow+profile,is_active,archived,pinned], total, limit, offset, storage}` (`sessions.py:177-240`). `GET /api/sessions/search?q=&profile=`, `GET /api/sessions/{id}`, `PATCH /api/sessions/{id} {title?,archived?,hidden?,pinned?,unread?,profile}`, `DELETE`, `GET …/export`. `GET /api/profiles/sessions` / `/sidebar` lists across profiles.

---

## 5. Everything else useful

- **Health/status:** `GET /api/health` (public, cheap: `ok, version, commit, auth_required`), `GET /api/status` (public: version, gateway state/platforms, `active_sessions`, `auth_*`, `install_id`, memory/disk, `profiles`) (`web_routers/status.py:116, 466`). `GET /api/system/stats`, `GET /api/logs`. Live example in section 2.1.
- **Cron / routines** (`web_routers/cron.py:668-740`): `GET /api/cron/jobs?profile=all`, `GET /api/cron/jobs/{id}`, `GET …/runs?limit=`, `POST /api/cron/jobs?profile=` `{schedule, prompt, name?, deliver:"local"|platform, repeat?, skills?, model?, provider?, enabled_toolsets?, workdir?, paused?}` (`web_models.py:310-330`), `PUT /api/cron/jobs/{id} {"updates":{…}}`, `POST …/pause|resume|trigger`, `DELETE`, `GET /api/cron/delivery-targets`, `GET /api/cron/blueprints` + `POST /api/cron/blueprints/instantiate`. Runs are sessions `cron_<job>_<time>` (final reply = output). WS event `cron.changed` signals refresh.
- **Files:** `GET /api/files`, `/api/files/read`, `/api/files/download`, `POST /api/files/upload`, `/api/fs/list|read-text|write-text`, `GET /api/media?path=` (agent-produced media).
- **Voice:** `POST /api/audio/transcribe?profile= {"data_url":"data:audio/m4a;base64,…","mime_type"}` -> text (`audio.py:83`); `POST /api/audio/speak?profile= {"text"}` -> audio data URL (`audio.py:292`); `GET /api/audio/voice-config`; streaming WS `/api/audio/transcribe-stream`, `/api/audio/speak-stream`; RPC `voice.*`.
- **Memory:** `GET /api/memory`, memory providers routes; analytics `GET /api/analytics/usage?days=`, `/api/analytics/models`.
- **Gateway ops:** `POST /api/gateway/restart`, `GET /api/hermes/update/check`.
- **Plugins:** Hermex ships a `hermex-push` dashboard plugin (`/api/plugins/hermex-push/pairing`) for APNs push; kanban plugin has its own WS `/api/plugins/kanban/events?ticket=`.

---

## 6. Minimal native client recipe

1. `GET /api/status` -> verify `auth_required`, `basic`, version >= 0.21.5, pin `install_id`.
2. `POST /auth/password-login` (cookie jar) [or native PKCE for bearer tokens].
3. `GET /api/auth/me`.
4. REST: `profiles.list` via WS or `GET /api/profiles`; `GET /api/sessions?profile=…&order=recent`.
5. `POST /api/auth/ws-ticket` -> open `wss://host/api/ws` with `Sec-WebSocket-Protocol: hermes-gateway-v1, hermes-gateway-ticket.<t>` -> read `gateway.ready` -> send `client.capabilities {server_requests:true}` -> start 15 s `gateway.ping`.
6. Chat: `session.resume {session_id:<stored>, profile, inline_images:false}` or `session.create {profile}` -> `prompt.submit {session_id:<runtime>, text}` -> render events filtered by `params.session_id` -> `message.complete`. Stop = `session.interrupt`.
7. On socket drop: new ticket, reconnect, `session.resume`, `session.events.since {last_seen}`; re-deliver `open_requests`.
8. On REST 401 `session_expired`: re-login.

## 7. Hermex notes (public, MIT: github.com/uzairansaruzi/hermex)
- Two server kinds: **Webui server** (the separate community `hermes-webui`, password+cookie) and **Hermes server** (the official dashboard, direct, "Bot Mode", opens on a Bots inbox) (`CONTEXT.md`). The Hermes-server path is what this report describes.
- Sign-in: `HermesConnection.swift:130-165` (status -> `POST auth/password-login {provider:"basic",…}` -> `GET api/auth/me` must be `provider:"basic"`; non-basic providers are "browser sign-in", not yet supported). WS: `HermesGateway.swift:263-300` (fresh ticket per socket, `gateway.ready` check, `client.capabilities`, 15 s heartbeat, 30 s RPC deadline, close on background, reconnect on active). REST catalogue: `HermesREST.swift`.
- Avatars are read from/written to `ui_meta["hermes-bots"]` + `profiles.set_asset`, so they sync with Hermes Desktop; `expression` is Hermex-only.
- Cannot use a dashboard served under a path prefix yet; supports custom headers per connection for Cloudflare Access.

Sources: [Hermex repo](https://github.com/uzairansaruzi/hermex), [Hermex overview (scriptbyai)](https://www.scriptbyai.com/hermex-hermes-agent-iphone/), [Cloudflare Tunnel + Access + Hermex (dev.to)](https://dev.to/mosesman831/self-hosted-hermes-agent-on-ios-cloudflare-tunnel-access-service-tokens-hermex-103e), [Hermex review (tonyreviewsthings)](https://www.tonyreviewsthings.com/hermex-ios-app-review/), [hermes atlas entry](https://hermesatlas.com/projects/uzairansaruzi/hermex); NousResearch/hermes-agent source at tag v0.21.7 (local checkout).
