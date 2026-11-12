# Connection page: a connection's tools (#324)

Info > Connections shows "Connected · 3 tools" but never the tools. Tapping a connection opens a **Connection page** with its details, Test Connection, and every tool's name and description with an estimate of what the tools cost in context. Read only and Crew only: everything comes from `POST /api/mcp/servers/{name}/test` (already called when Info opens) and `GET /api/mcp/servers` (already loaded). No new Hermes verb, no new write. Switches per tool, Edit, Change API Key and Remove on the page are #326.

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
   - Connected: one row per tool in Hermes' order: name (body, one line, middle truncation), description (subheadline, secondary, wraps). A tool the filter keeps from the bot shows a trailing secondary "Off" and is left out of the estimate. Footer: "These tools use about 276 tokens of Ada's context in every chat." when there is an estimate, and "1 tool is turned off for Ada and isn't counted." when a filter turns tools off.
   - More than 20 tools: a search field (`.searchable` on iPhone, a search `TextField` row at the top on the Mac, the Add Connection sheet's pattern) filtering by name and description; no match shows `ContentUnavailableView.search`.
   - Zero tools: "This connection offers no tools."
   - Checking (no test yet): a small spinner.
   - Off: "Turn the connection on to see its tools."
   - Needs Sign-In: "Sign in to see its tools." and a **Sign In** button (the row's flow, `webAuthenticationSession` + polling; disabled offline); while signing in, **Cancel**.
   - Failed: "Tools appear when the connection works."
5. Offline: the page stays readable with the last answer; Test Connection and Sign In are disabled.

## Long content

Names and addresses truncate in the middle on one line; descriptions wrap (at most about 80 characters); errors wrap to three lines in the header and fully in the Test footer. The Mac sheet has a fixed size and scrolls; the iPhone page scrolls. Dynamic Type grows rows.

## Verification

- Unit (`ConnectionsTests`): the recorded deepwiki `/test` answer decodes descriptions and `schema_chars`; the estimate is 276; a recorded `GET /api/mcp/servers` with `tools.include`/`exclude` (globs, a single string, `include: []`) marks the right tools off and drops them from the estimate; a tool list without `schema_chars` gives no estimate.
- Real server on `crew-test`: add `deepwiki` (catalog), a bogus-URL server and `linear` (never signed in), give deepwiki a `tools.exclude` glob and linear a single-string `tools.include` (recorded as the filter fixture); compare `/test` with what the page lists; remove all three and check the list is empty.
- UI: the Connection page sheet stays open (the #222 failure mode), in `InspectorUITests`, run locally on a private simulator.
- Renders: iPhone and Mac, light and dark, through the real `BotInspector` presenter: connected deepwiki page, plus the failed and Needs Sign-In pages.
