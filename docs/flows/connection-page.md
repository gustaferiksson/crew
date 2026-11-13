# Connection page: a connection's tools (#324)

Info > Connections shows "Connected · 3 tools" but never the tools. Tapping a connection opens a **Connection page** with its details, Test Connection, and every tool's name and description with an estimate of what the tools cost in context. Everything comes from `POST /api/mcp/servers/{name}/test` (already called when Info opens) and `GET /api/mcp/servers` (already loaded). #326 adds the writes: a switch per tool, Change Address, Change API Key and Remove (see Editing below).

## What Hermes 0.23.1 answers

- `/test` ok: `{ok, tools: [{name, description, schema_chars?}], prompts, resources}`. Descriptions are cut to 80 characters by Hermes (`_probe_single_server`, `desc[:77] + "..."`), so a description never needs more than a few lines and there is no fuller text to show elsewhere. `schema_chars` is optional (older servers, failed schema conversion).
- `/test` lists **every** tool the server offers. The server entry's `tools` filter from `GET /api/mcp/servers` (`tools.include`, a whitelist that wins, even `[]`; else `tools.exclude`; each a name or an fnmatch glob; a single string counts as one entry; `tools/mcp_tool_registration.py` `_make_tool_filter`) decides which ones the bot actually gets. The real `default` profile uses `tools.include` on both its servers.
- The OAuth poll's `approved` answer carries `tools` without `schema_chars`; until the next Test the page shows the tools with no estimate.

## Token estimate (Hermes Desktop's `lib/mcp-cost.ts`)

Sum of `ceil(schema_chars / 4)` over the tools the filter lets through, skipping tools without a positive `schema_chars`. No such tool, no estimate. deepwiki's three tools (510, 287, 302) give 128 + 72 + 76 = 276. The schemas ride along with every model call, so they take that much of the context the chat's context ring shows.

## Opening it

- **Row:** an ⓘ button (`info.circle`, borderless, tint) before the switch opens the page, as Wi-Fi and Bluetooth do for a row with its own trailing control; the rest of the row is unchanged (switch, inline Sign In / Cancel, red failure text, swipe to Remove). The context menu gains **Show Details** and VoiceOver gets the same action.
- **iPhone and Mac: a sheet** from `BotInspector`, like every other inspector sub-page (Capabilities, Add Connection, conversation transcripts): `NavigationStack`, title the server's name, **Done**; 420 x 560 pt on the Mac like Add Connection. Not a push: PLAN.md keeps "Nothing pushes from the inspector", and a push here would cancel the inspector's `.task` that runs the `/test` calls (a row still Checking… would be stored as a cancelled failure and never retested) and rerun the profile load, routines, conversations and the "Saved" flash on the way back. The Mac inspector column has no navigation stack either.
- `BotInspector` owns the presented server; the row only sets it. The page reads the live store by the server's name, so a Test, a sign-in or a reload updates it. If the server disappears (removed elsewhere, then reloaded), the page shows "This connection was removed." with no controls.

## Page (grouped Form)

1. **Header:** icon tile, name (headline, middle truncation), status line as in the row (Connected · 3 tools, Checking…, Off, Needs Sign-In in orange, Waiting for sign-in…, red error up to three lines).
2. **Details:** the **Enabled** switch (the row's switch and store call, not a new write; absent for plugin servers, which show "From <plugin>"), Address (URL servers) or Command (command and arguments) as selectable text truncated in the middle, Sign-In: None, API Key or Sign In (`auth` nil/none, header, oauth).
3. **Test Connection** button (spinner while testing; disabled offline, while Off, while busy or signing in). Footer: Hermes' error in red when the test failed.
4. **Tools** (header "Tools", count in the header when connected):
   - Connected: one row per tool in Hermes' order, a `Toggle` whose label is the name (body, one line, middle truncation) over the description (subheadline, secondary, wraps); on means the server's filter lets the tool through. A tool that is off is left out of the estimate. Footer: "These tools use about 276 tokens of Ada's context in every chat." when there is an estimate, then "Changes apply to new chats." always.
   - More than 20 tools: a search field (`.searchable` on iPhone, a search `TextField` row at the top on the Mac, the Add Connection sheet's pattern) filtering by name and description; no match shows `ContentUnavailableView.search`.
   - Zero tools: "This connection offers no tools."
   - Checking (no test yet): a small spinner.
   - Off: "Turn the connection on to see its tools."
   - Needs Sign-In: "Sign in to see its tools." and a **Sign In** button (the row's flow, `webAuthenticationSession` + polling; disabled offline); while signing in, **Cancel**.
   - Failed: "Tools appear when the connection works."
5. **Remove Connection…** (destructive button, its own section at the bottom; absent for plugin servers): the row's confirmation ("Remove deepwiki from Ada?", "Ada loses these tools in new chats.", Remove / Cancel), presented from the page's `Form`; on success the sheet closes, as Contacts' Delete and Wi-Fi's Forget This Network return to the list ("This connection was removed." stays for removals made elsewhere). Hermes keeps the connection's `.env` key and OAuth token file; Crew doesn't delete them.
6. Offline: the page stays readable with the last answer; every switch and button is disabled.

## Editing (#326)

### Write verbs (Hermes 0.23.1 source)

- Hermes has no single-server update. Tool switches and Change Address save with the whole-map `PUT /api/mcp/servers {servers, profile}` (`web_routers/mcp.py` `replace_mcp_servers`, `mcp_config.py` `_replace_mcp_servers`), Hermes Desktop's save path (`use-mcp-servers.ts` `writeEntry`). It validates every entry (`validate_mcp_server_entry`) and writes nothing when one fails, answering 400 with the issues.
- The map is built from a fresh `GET /api/config?profile=<bot>&include_defaults=false` read right before every write (`read_raw_config`: the file as written, `${VAR}` references intact, nothing masked). Never from the default read (`load_config()` is env-expanded, so it would write plaintext tokens into `config.yaml`) and never from `/api/mcp/servers` summaries (masked, and missing keys like `headers`, `timeout`, `oauth`). Crew changes one key of one entry in that read and sends every other entry back as read.
- Crew never PUTs unless the fresh read decoded to an object whose `mcp_servers` holds the target: Hermes treats an empty map as "remove every server".
- Change API Key is WS `mcp.servers.set_api_key {name, value, profile}`: the key goes to the bot's `.env` (`MCP_<NAME>_API_KEY`) and `config.yaml` keeps `Authorization: Bearer ${MCP_<NAME>_API_KEY}`. `profile` is always sent, because without it Hermes writes the launch (default) profile.
- Remove is the existing `DELETE /api/mcp/servers/{name}`.
- Every change applies to the next chat; nothing restarts.

### Tool switches

- Desktop's rule (`lib/mcp-tool-filter.ts`): when the entry has `tools.include` (even empty, or a single string, which Hermes' runtime counts as one name and a switch turns into a one-item list), switching a tool adds or removes its name there and `include` stays; otherwise it adds or removes the name in `tools.exclude`, and an emptied `exclude` (and then an empty `tools`) is removed. The switch sets the state it shows, so a repeated save is harmless.
- A tool whose state comes from a glob pattern (`read_wiki_s*`) has its switch disabled, since adding or removing a name can't change it; the Tools footer adds "Tools matched by a pattern in Hermes' config can't be switched here."
- While one save runs, every tool switch and button of that connection is disabled (two overlapping read-modify-writes would lose one), and the Test Connection row shows its small spinner.
- The Tools header count and the row's "Connected · 3 tools" stay the number the server offers (from `/test`); the estimate updates as soon as a switch moves, since it counts only the tools that are on.
- The switch moves at once; a failed save puts it back (reload of `/api/mcp/servers`) and shows the error.
- Disabled when offline, while the connection is Off, for plugin servers and when not connected (no tool list).

### Change Address (URL servers)

- A **Change Address…** button in Details opens an alert with a URL field (URL keyboard and content type, no autocapitalization or autocorrection) prefilled with the address, **Save** / Cancel; message "deepwiki is tested again with the new address. Changes apply to new chats." Save is disabled until the text is an http(s) URL with a host and differs from the current one. On success Crew tests the connection again, unless it is Off. An OAuth connection's token belongs to the old host, so it usually shows Needs Sign-In afterwards.
- Only `url` changes; headers, auth, the tool filter and every other key stay as read. Renaming and editing a command server's command, arguments or environment stay Remove and Add (a hand-written entry can hold inline secrets that a form would show, and a rename moves the OAuth token file and the key's variable name).

### Change API Key (API Key servers, `auth: header`)

- A **Change API Key…** button in Details opens an alert with an empty `SecureField` "API Key", **Save** / Cancel; message "The old key is replaced. Changes apply to new chats." The old key is never read or shown.
- Hermes replaces the entry's whole `headers` and, without `env_var`, points it at `MCP_<NAME>_API_KEY`. So on Save Crew first reads the raw entry: only when `headers` is exactly `Authorization: Bearer ${VAR}` (what Crew's and Hermes' API Key flow writes) does it call `set_api_key` with `env_var: VAR`; any other shape (extra headers, a literal token) shows "deepwiki's headers were written by hand. Change its key on the server." and writes nothing.
- On success Crew tests the connection again.

### States

- Saving: the Test Connection row's spinner, the connection's switches and buttons disabled.
- Error (offline mid-save, timeout, Hermes 400 validation detail, 5xx): the text in red in the Test Connection footer, directly above Tools; a rejected PUT writes nothing (all or nothing), and since a timed-out PUT may still have landed, the page reloads the server list so the switches show what is saved.
- Conflict: the change is applied to the entry as just read, so a change made elsewhere to another key or another connection is kept. When the fresh read no longer has the connection: "deepwiki was removed on the server." and the list reloads (the page then shows "This connection was removed."). The PUT itself is unversioned, so two clients saving in the same instant can still overwrite each other: a Hermes limitation, stated, not worked around.
- Hermes writes YAML in the order it receives, so Crew keeps the read's order: it splices the raw JSON text, sending every other server's text exactly as read in the read's order, and the edited entry's keys in their original order (a new key such as `tools` goes last). A single switch never reshuffles `config.yaml`.

## Long content

Names and addresses truncate in the middle on one line; descriptions wrap (at most about 80 characters); errors wrap to three lines in the header and fully in the Test footer. The Mac sheet has a fixed size and scrolls; the iPhone page scrolls. Dynamic Type grows rows.

## Verification

- Unit (`ConnectionsTests`): the recorded deepwiki `/test` answer decodes descriptions and `schema_chars`; the estimate is 276; a recorded `GET /api/mcp/servers` with `tools.include`/`exclude` (globs, a single string, `include: []`) marks the right tools off and drops them from the estimate; a tool list without `schema_chars` gives no estimate.
- Real server on `crew-test`: add `deepwiki` (catalog), a bogus-URL server and `linear` (never signed in), give deepwiki a `tools.exclude` glob and linear a single-string `tools.include` (recorded as the filter fixture); compare `/test` with what the page lists; remove all three and check the list is empty.
- Unit (#326, `ConnectionEditTests`): the raw `mcp_servers` text recorded on crew-test (an API Key server `wikikey` holding `${MCP_WIKIKEY_API_KEY}`, then deepwiki, out of alphabetical order) goes through a tool switch and Change Address via a stubbed transport that answers the env-expanded config unless the read carries `include_defaults=false`; the PUT body keeps the read's server order and each entry's key order, the other entry's text is identical to the read, every reference survives, and only the target key changed. Shown failing without `include_defaults=false`. A read without `mcp_servers` or without the target sends no PUT. Filter edits follow Desktop's rule (include kept, emptied exclude dropped, globs not switchable).
- Real server (#326, `Tests/connection_probe`, through `BotConnections`): add deepwiki, switch one tool off, check `/test` and the raw config (`tools.exclude` only on that entry), turn it back on; add a dummy API Key server, rotate its key, check the config still holds `${MCP_..._API_KEY}` and `GET /api/env` says `is_set`; a PUT Hermes rejects leaves the config unchanged; remove everything and its `.env` key so `crew-test` ends with no servers.
- UI: the Connection page sheet stays open (the #222 failure mode), in `InspectorUITests`, run locally on a private simulator.
- Renders: iPhone and Mac, light and dark, through the real `BotInspector` presenter: connected deepwiki page, plus the failed and Needs Sign-In pages.

## Add to Other Bots (#205, first slice)

Giving one connection to several bots today means Add Connection on each. This slice adds it from a Connection page to bots the user picks, copying the entry as written. It is not #205's library: nothing is stored in Crew, and assignment is not tracked.

### How the key moves (Hermes 0.23.1)

It doesn't. No verb copies a `.env` value from one existing profile to another: `mirror_credentials` (`tui_gateway/methods_profiles.py:548` `_mirror_launch_credentials`) copies the launch profile's `.env` once, at create; `PUT /api/env` (`hermes_cli/web_routers/config_env.py:333`) needs the value in the body; the only way to read one back is `POST /api/env/reveal` (`:1098`, plaintext, rate limited, audit logged), which Crew never calls. A `${VAR}` reference resolves only from its own profile's scope (`tools/mcp_tool_config.py:210`, "a profile that lacks the name gets nothing, never another profile's token"). So:

- A connection whose `${VAR}` references are all set on the target (`GET /api/env?profile=<target>` `is_set`, the check New Bot's copy already makes, #327) is added with the references; the target uses its own value.
- A connection referencing a variable the target lacks is skipped: "Skipped: no deepwiki API key on this bot."
- OAuth (`auth: oauth`): added; tokens are per profile (`mcp-tokens/<name>.json`), so the row says "Added. Needs Sign-In." (orange) and the target's own Connections row shows Needs Sign-In.
- A literal secret written into the entry is skipped: "Skipped: deepwiki's key is written in its config." One name rule (contains KEY, TOKEN, SECRET, PASSWORD or AUTH, case-insensitive) over header names, `env` names, URL query item names and `--flag value` / `--flag=value` arguments, plus `oauth.client_secret` and a password in the URL (`user:pass@`), whenever the value holds no `${VAR}`. Copying it would put a plaintext key into another bot's config. New Bot's copy (#327) gets the same rule, and its "wasn't copied: its key stays with Hermes" sentence covers it.

### Write

- Source entry: from `GET /api/config?profile=<source>&include_defaults=false` (raw, `${VAR}` intact; the default read is env-expanded and would carry the resolved key). The entry's JSON text is taken as read.
- Target: per bot, a fresh `GET /api/config?profile=<target>&include_defaults=false` right before the write, then the whole-map `PUT /api/mcp/servers {servers, profile}` (#330's path: `replacingServer`'s splice extended to append): every existing member's text as read, in the read's order, and the new entry's text appended. Before sending, the body is decoded and must equal the read's map plus exactly that one entry, else nothing is sent. A read that is a JSON object without `mcp_servers` (or with `null`) counts as an empty map (a fresh bot); any other shape writes nothing. The target read is raw for the same reason as the source: the PUT rewrites every entry, so an env-expanded read would write the target's own keys in plaintext.
- WS `mcp.servers.add` would also add one entry, but the #330 path is already verified on the real server; the future library can switch.
- Bots are written one after another; each is independent, a failure on one doesn't stop the rest and needs no rollback (the PUT is all or nothing per bot).
- Every change applies to new chats; nothing restarts.

### Surfaces

- **Connection page:** an **Add to Other Bots…** button in Details, after Change API Key. Absent for plugin servers (not in the raw config) and when there are no other bots; disabled offline, while busy or signing in.
- **Picker:** pushed inside the Connection sheet's `NavigationStack` (iPhone and Mac) by `navigationDestination(isPresented:)` attached to the page's `Form` itself (never inside a Section), title "Add to Other Bots". A grouped `Form`, one row per other bot that isn't hidden, in the bot list's order (groups and rooms aren't bots and never appear; hidden bots stay out, as in New Group's member picker). Each row is New Group's member row: avatar 28 pt, title (middle truncation), trailing `checkmark.circle.fill` in the tint when picked or a secondary `circle`, the whole row a plain button; VoiceOver gets the `.isSelected` trait. The same row on Mac, matching New Group there. Toolbar: **Add** in the `.confirmationAction` placement (no dialog), disabled until a bot is picked and while offline. Footer, built from the connection's Sign-In kind: "deepwiki is added with its settings." plus "A bot without its own deepwiki API key is skipped." for API Key (`auth: header`), and "Each bot signs in separately." for Sign In (`auth: oauth`).
- **Adding:** bots are written one after another; the row being written shows a small spinner, the queued ones "Waiting", rows stop toggling, Add disables, and Back and swipe-to-dismiss are off (`navigationBarBackButtonHidden`, `interactiveDismissDisabled`) for the few seconds it takes.
- **Result:** each picked row shows its outcome under the title (subheadline): "Added" (secondary), "Added, turned off" when the source connection is Off (copied as written, so it stays Off on the target), "Added. Needs Sign-In." (orange, the row's status vocabulary), "Already has deepwiki" (secondary; same name and same URL, or same command and arguments), "Skipped: a different deepwiki is already on this bot." (never overwritten), the two key skips above (secondary), or Hermes' error in red (offline mid-write, timeout, 400 detail such as a plugin name collision, 5xx). Unpicked rows are unchanged. Add then disappears and Back returns to the Connection page, whose Done closes the sheet; going in again starts fresh.
- Not in this slice: showing which bots already have the connection before Add (it needs a `GET /api/mcp/servers` per bot; #205's library derives that). The write-time check is the guard.
- **Source removed meanwhile:** the source read lacks the entry: every picked row shows "deepwiki was removed on the server." and nothing is written.
- **Offline:** Add disabled, footer adds "Crew is offline."; going offline mid-run shows the network error on the rows not yet written.
- **Long content:** bot titles and connection names truncate in the middle; outcome text wraps; the list scrolls; Mac sheet keeps 420 x 560.
- **Other surfaces:** the target bots' Info > Connections show the new row the next time their inspector opens (it loads on open); nothing in the chat, the bot list, push or the source bot changes. Light and dark: system Form colours only.

### Verification

- Unit (`AddToBotsTests`), stubbed transport answering env-expanded config unless the read carries `include_defaults=false`, over recorded raw configs (source `config-raw.v0.23.1.json`, a target recorded on a throwaway bot that already holds a `${VAR}` entry): the PUT holds the reference, never the resolved value, and the target's existing entries keep their text and order (two tests, one per read, each shown failing without its `include_defaults=false`); a missing key, a literal secret, a same-name different server, and the same server each send no PUT and give their outcome; OAuth gives "sign in"; a target read without `mcp_servers` appends to an empty map; a non-object read sends nothing. New Bot's literal-secret skip.
- Real server (`Tests/connection_probe/run.sh addto`): deepwiki and a dummy key server on crew-test; two throwaway `crew-test-add-*` bots (`mirror_credentials: false`), one given its own dummy value for the key variable; add both connections to both; raw configs hold only references, no dummy value; `/test` ok for deepwiki on both and the key server on the keyed bot; a second run says Already has; cleanup deletes the bots and leaves crew-test with `{"servers":[]}` and no dummy key.
- Renders: picker with two bots picked, and the result with each outcome, iPhone and Mac, light and dark.
- PLAN.md Decisions gets a line for Add to Other Bots, and the New Bot line notes the literal-secret skip.
