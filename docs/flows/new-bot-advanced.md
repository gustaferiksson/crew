# New Bot: Advanced (#119)

New Bot keeps its basic fields (name, title, role, look, Duplicate From, description, instructions). One **Advanced** row at the end of the form pushes a Form page, on iPhone and Mac alike (the same pattern as Appearance), so the sheet's height is unchanged and #175's short-screen fit can't regress. Untouched, Advanced sends exactly what New Bot sent before.

## What Hermes 0.22.5 accepts (checked on the server with `crew-test-adv*` throwaways, deleted after)

- `profiles.create` takes `name, description, soul, clone_from, model, provider, mirror_credentials, share_auth, clone_all, no_skills, no_alias` and rejects every skill, toolset or MCP list. `model`/`provider` at create came back `model_set: false` every time, so the model is set after create.
- `mirror_credentials: false` creates the bot without the default profile's `.env`, `auth.json` and voice keys (`mirrored` all false). Default is true.
- `no_skills: true` leaves only Hermes' own `hermes-agent` skill (53 bundled otherwise). The per-skill list of a fresh bot is unknowable before it exists, so per-skill choices stay in the inspector.
- Toolsets: `PUT /api/tools/toolsets/{name}` on the new bot after create (the inspector's call).
- Model: `profiles.configure {model, provider}` after create (the inspector's `changeModel`); it may answer `confirm_required`.
- MCP: a new bot has no servers. Copying one means writing the default profile's raw `mcp_servers` entry into the new bot's config (`GET /api/config?profile=default`, then `PUT /api/config?profile=<new>` with only the chosen entries, deep-merged). Verified: the copied `files` server tested ok with 9 tools. Cloning (`clone_from`) already copies the source's servers.

## Advanced page

- **Model** picker: "Server Default" (or "Same as <source>" when duplicating) then the providers and models from `model.options` for the default profile (or the source). Server default sends nothing.
- **Copy API Keys** switch, on. Off sends `mirror_credentials: false`.
- **Bundled Skills** switch, on, hidden while duplicating. Off sends `no_skills: true`.
- Footer: where keys come from (the default bot's title) and that single skills are set later in the inspector.
- **Toolsets** row with "N On", pushing a Form of switches (label and tool summary), seeded from the default profile (or the source). Only the switches the user flips are saved after create.
- **Connections** section, only when not duplicating and the default profile has config servers: one switch per server (title, address truncated in the middle), all off. Footer: copied from the default bot; some need Copy API Keys or a new sign-in. Plugin servers are left out (not in config). Managing connections stays in the inspector's Connections section.

## After Create

1. `profiles.create` with name, description, soul, clone_from, and the key and skills switches. A failure keeps the sheet open with Hermes' message, as before.
2. Flipped toolsets, copied connections, then the model.
3. All applied: the sheet closes and selects the bot, as before.
4. The model needs confirmation: an alert "Use This Model?" with Hermes' message, **Use Anyway** (confirms and closes) / **Keep Default** (closes; the bot keeps the server default).
5. A step failed: the bot exists, so the sheet can't retry under the same name. An alert "Bot Created" lists what wasn't applied ("toolsets", "connections", "model") and says to change it in the inspector; OK closes into the bot. Both alerts merge into one when both happen.

## States

- Loading: the Toolsets page shows a spinner until the list arrives; the model picker shows only its default row; Connections is absent until loaded.
- Empty: no config servers on the default profile, no Connections section.
- Offline: Create is disabled (unchanged); the page keeps what it loaded.
- Error loading: same as loading (each list is optional, Advanced still creates a default bot).
- Long content: model ids and connection addresses truncate on one line; footers wrap.
- iPhone (pushed page in the sheet) and Mac (pushed in the sheet's NavigationStack), light and dark, system Form styling. Renders: `new-bot`, `new-bot-advanced`.
