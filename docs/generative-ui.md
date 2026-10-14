# Generative UI in Crew

Research date 2026-10-14. Read-only research: no app code, server config or plugins touched. Status: implemented with Header, Steps, Badge, Table, KeyValue, Chart and Map in `crew/v1` (see the Generative UI lines in `docs/PLAN.md` Decisions; Rich UI installs and toggles a bundled `crew-ui` skill). Hermes refs are against the local checkout `~/.hermes/hermes-agent` (`0.21.7+302`, the server runs `v0.21.7`; none of the files cited differ in a way that matters here).

Goal: let a bot put rich native components in the chat (approval with context, recipe, checklist, table, chart, form, card with actions, map) with as little custom engineering as possible.

## TL;DR

Adopt **A2UI v0.9.1** with Google's **official Swift renderer** (`A2UISwiftUI` + `BasicCatalogSwiftUI` in [a2ui-project/a2ui](https://github.com/a2ui-project/a2ui/tree/main/swift)). The agent writes A2UI messages in a fenced ` ```a2ui ` block inside its normal reply; Crew renders it natively, and taps/forms go back as a hidden `prompt.submit`, the same talk-back path Hermes Desktop's widgets already use. Zero server code, nothing to install on the host, works in history and across devices because it is just transcript text. Keep Hermes' own `::preview{file=}` HTML widgets (in a sandboxed `WKWebView`) as a later escape hatch for arbitrary visualisations.

## 1. What Hermes already has

| Surface | What it is | Useful to Crew? |
|---|---|---|
| Server requests `approval`, `clarify`, `setup_choose`, `sudo`, `secret`, `vault.*` (`tui_gateway/contracts/server_requests.py`) | Fixed-shape blocking questions. `approval` allows extra context keys (`model_config extra: allow`); `setup_choose` is an onboarding card picker with a closed `kind` enum | Already rendered (approval/clarify). Not extensible: a new shape needs a Hermes core change |
| `terminal.read`, `preview.read`, `preview.act`, `window.read`, `tour` | Desktop GUI bridges (read the in-app browser pane, drive a guided tour). Probe-and-give-up if no client answers (`tui_gateway/server.py:1444-1530`) | No. Desktop-only, not generative UI. Crew should keep declining them (4404) |
| `desktop_ui` toolset: `desktop_preview` open/close/read, `focus_pane`, `apply_layout`, `react_to_message` (`tools/desktop_ui.py`, `tools/preview_tool.py`) | Emit renderer events only when the gateway runs inside Desktop (`HERMES_DESKTOP=1`) | No, not offered to dashboard clients |
| **`::preview{file="x.html"}` transcript directive** (`apps/desktop/src/components/assistant-ui/inline-preview-directive.tsx`) | Agent writes a single-file HTML widget to disk and references it on its own line. Desktop renders it live in a sandboxed iframe (`allow-scripts`, no same-origin), injects theme CSS vars, auto-sizes, and `data-hermes-send="prompt"` / `window.hermes.send()` sends a **hidden user turn** (`prompt.submit {display_kind: "hidden"}`) | Yes, as an escape hatch (option 2 below). The talk-back mechanism is the one Crew should reuse for everything |
| `::name{key="v"}` plugin directives (`apps/desktop/src/lib/transcript-directives.ts`) | Desktop plugins claim a directive name; unclaimed ones stay prose | Pattern only (Desktop renderer plugins, TypeScript) |
| Rich fences ` ```mermaid `, ` ```svg `, ` ```listing ` (`embeds/registry.tsx`), artifact cards for big html/svg/code fences, GitHub alerts, YouTube/Spotify embeds | Desktop markdown extensions | Shows the fence convention is already Hermes' house style for rich content |
| `MEDIA:/abs/path` | File/image delivery on messaging platforms and Desktop | Separate, already partly handled by attachments |
| MCP tool results (`tools/mcp_tool_content.py`) | Text, images cached to `MEDIA:` tags, resources flattened to text; `_meta` filtered, `ui://` resources never surfaced | No MCP Apps support at all |
| Plugin API (`hermes_cli/plugins.py`) | `register_tool`, `register_system_prompt_section`, hooks (`transform_tool_result`, `transform_llm_output`, `pre_llm_call`, ...) | Enough for a `render_ui` tool if ever needed |

How the agent is told: Desktop's recipe lives in `PLATFORM_HINTS["desktop"]` (`agent/prompt_builder.py:740-757`). A dashboard gateway session gets platform **`tui`** unless the server runs with `HERMES_DESKTOP=1` (`_resolve_session_platform`, `tui_gateway/server.py:1564`), and the `tui` hint says nothing about widgets. `client.capabilities` rejects unknown keys, so Crew cannot announce "I render X" per connection. Teaching must therefore be **per profile** (see section 5).

Hermex: MarkdownUI + code highlighting + LaTeX + tables + inline images; nothing generative (`docs/hermex-features.md` section 3). Hermes Desktop: everything above.

## 2. Options ranked by what Crew would build and maintain

| # | Option | Format | Native SwiftUI | Actions back to agent | Security | Maturity | Crew effort |
|---|---|---|---|---|---|---|---|
| 1 | **A2UI v0.9.1, official Swift renderer** | Declarative JSON: flat component list + JSON-pointer data model + actions | Yes, `Surface(viewModel:catalogs:)`, custom components via `ComponentImplementation` | Client action `{name, surfaceId, sourceComponentId, timestamp, context}` | Data only, schema-validated (JSON Schema 2020-12) on device, no code execution | Spec v0.9.1 stable, v1.0 RC due Q4 2026 ([roadmap](https://a2ui.org/roadmap/)). Swift renderer: official, in main, v1.0 support merged 2026-10-07, commits daily, **no tagged Swift release** (pin a commit). Apache 2.0 | **Low**: fence extractor, action bridge, glass shell, 2 to 4 custom components |
| 2 | Hermes `::preview{file=}` HTML widget in `WKWebView` | Agent-authored HTML/JS file on the host | No (web content) | `window.hermes.send` → hidden turn | Crew owns the sandbox: non-persistent `WKWebsiteDataStore`, content rules blocking network, no navigation, size caps | Shipping in Desktop; agent recipe already written | Medium: directive parser, fetch via `/api/fs/download`, theme prelude, JS bridge, height measuring, scroll perf in `LazyVStack`. File can vanish from disk, breaking history |
| 3 | Community `a2ui-swift` ([BBC6BAE9/a2ui-swift](https://github.com/BBC6BAE9/a2ui-swift)) | A2UI v0.8 to v0.9.1 | Yes (SwiftUI, UIKit, AppKit) | Closure on `A2UISurfaceView` | Same as 1 | MIT, 64 stars, v0.3.5, last push 2026-09-24, one maintainer | Same as 1, more bus-factor risk. Fallback only if the official package fails to build |
| 4 | MCP Apps ([SEP-1865](https://modelcontextprotocol.io/seps/1865-mcp-apps-interactive-user-interfaces-for-mcp), [overview](https://modelcontextprotocol.io/extensions/apps/overview)); OpenAI Apps SDK widgets are the same iframe model | `ui://` HTML resource (`text/html;profile=mcp-app`) + postMessage JSON-RPC (`ui/initialize`, `tools/call`, `ui/message`) | No; only web hosts ([`@mcp-ui/client`](https://github.com/MCP-UI-Org/mcp-ui) is React) | `tools/call` proxied through host, `ui/message` | iframe sandbox + CSP | Stable spec, hosts: Claude, VS Code, Goose, M365 Copilot | High: Hermes core never forwards `_meta.ui` or `ui://` resources to clients, so it needs server work **and** a webview AppBridge host |
| 5 | Adaptive Cards | Declarative JSON | Official iOS SDK is UIKit/ObjC++, no macOS ([MS docs](https://learn.microsoft.com/en-us/adaptive-cards/rendering-cards/getting-started)); SwiftUI port [AdaptiveCardUI](https://swiftpackageregistry.com/gonzalezreal/AdaptiveCardUI) archived 2021 | `Action.Submit` | Data only | Mature format, dead on Apple | High |
| 6 | AG-UI ([docs](https://docs.copilotkit.ai/ag-ui)), Vercel AI SDK / [json-render](https://infoq.com/news/2026/03/vercel-json-render), Open-JSON-UI | AG-UI is a transport (Hermes has its own); json-render and Vercel genUI are React; Open-JSON-UI is thinly specified | None (the [Swift AG-UI SDK](https://swiftpackageindex.com/paduh/ag-ui-swift) is transport only) | n/a | n/a | n/a | Out |
| 7 | Own catalog | Our JSON | Yes | Our choice | Ours | Ours | Highest: schema, renderer, prompt, versioning all ours. Only if 1 fails |

Apple has no generative-UI format; nothing in SwiftUI/App Intents applies. A [2026-08 survey](https://uzori.ai/blog/generative-ui-swift-not-react) reaches the same conclusion: A2UI is the only JSON contract with a native Swift renderer.

## 3. Delivery paths

| Path | Survives reload / syncs | Server work | Fallback in Hermex/Desktop | Verdict |
|---|---|---|---|---|
| (b) **Fenced block in the reply** (` ```a2ui ` holding a JSON array of A2UI messages) | Yes: it is `message.complete.text` and the REST history `content` | None | Renders as a code block (Desktop may promote a long one to an artifact card) under the agent's own prose summary | **Pick** |
| (a) `render_ui` tool from a `crew-ui` plugin | Yes: live `tool.start.args` carries full args (`tui_gateway/tool_progress.py:296-299`), history has `tool_calls[].function.arguments` | Plugin install + restart on the host; could wrap the A2UI Python SDK's `validate_payload` and prompt generator ([a2ui_agent](https://github.com/a2ui-project/a2ui/tree/main/python/a2ui_agent), incl. an ADK `SendA2uiToClientToolset`) | A tool row in the work log | Later upgrade if the model's JSON proves unreliable: server-side validation lets the tool return errors the model can fix in the same turn |
| (c) MCP Apps resource | n/a | Hermes core | n/a | No |
| (d) Server request round trip | No (requests are ephemeral, not in history) | Hermes core (closed request set) | Other clients must decline | No; only for things Hermes already asks (approval, clarify) |

The A2UI SDK's own wire form is `<a2ui-json>...</a2ui-json>` sentinel tags (its parser also strips a fence inside them, `direct_json/parser.py`). A fence is preferred here because markdown renderers in Hermex and Desktop degrade a fence to a readable code block, while a raw HTML-like tag may be dropped or shown as garbage. Crew's extractor can accept both.

**Actions back to the agent:** a button, checkbox submit or form submit produces the A2UI client action; Crew sends it as
`prompt.submit {session_id, text: "<a2ui-action>{…action JSON with resolved context…}</a2ui-action>", display_kind: "hidden"}`.
This is exactly Desktop's widget talk-back: a durable row the model sees, no user bubble (Crew already treats `hidden` rows that way, `Transcript.swift:138,179`). The agent replies with prose, a new or updated surface (`updateComponents`/`updateDataModel` on the same `surfaceId`), or both. Approvals that guard real commands stay on Hermes' `approval` server request; an A2UI approval card is for "should I do X?" decisions the agent asks about itself.

## 4. Recommendation and what Crew still writes

Use the official package (root `Package.swift` of a2ui-project/a2ui, tools 6.1, iOS 16 / macOS 14 floors, deps `swift-json-schema` + `Yams`). Products: `A2UISwiftCore`, `BasicCatalog`, `A2UISwiftUI`, `BasicCatalogSwiftUI`. It is `ObservableObject`-based (`@ObservedObject SurfaceViewModel`); mixing with Crew's `@Observable` stores is fine. Adding it is a PLAN.md Decisions line (first SPM dependency).

Crew writes:

1. **Extractor** (~40 lines): find ` ```a2ui ` fences (and `<a2ui-json>`) in assistant text, both live and from REST history; render the surface when the fence closes or on `message.complete` (no partial JSON healing needed). Replace the fence in the bubble with the surface; keep the prose around it.
2. **Surface store**: one `MessageProcessor` per chat, fed every block of the transcript in order so later `updateComponents`/`updateDataModel` patch earlier surfaces; a surface is drawn at the position of its `createSurface`. Cap payload size (e.g. 64 KB) and show a small "couldn't display" chip plus the raw block on parse or validation failure.
3. **Action bridge** (~30 lines): A2UI action → hidden `prompt.submit` as above; disable the surface's buttons while that turn runs; show a tiny "Sent: <label>" note so the user sees what they did.
4. **Glass shell + theme**: wrap `Surface` in Crew's card look (glass, 4 pt grid, light/dark) and override the few basic components whose default look clashes (Card, Button, CheckBox) through `ComponentImplementation` registration and the `a2uiTheme` environment.
5. **Custom catalog `crew/v1`** for what the basic catalog lacks: `Table` (Grid), `KeyValue`, `Chart` (Swift Charts: bar/line/pie), `Map` (MapKit pins). Each is a `ComponentAPI` JSON schema + a SwiftUI view.
6. **Snapshots + fixtures**: a `chat-a2ui` snapshot with one of each MVP surface, light/dark, both platforms.

MVP slice, all basic catalog unless noted:

| Need | A2UI composition |
|---|---|
| Card | `Card` > `Column` (`Text` h, `Text` body, `Image`) |
| List / checklist | `Column`/`List` of `CheckBox` bound to `/items/i/done`, a "Done" `Button` sending the data model |
| Buttons → reply | `Row` of `Button` with `action.name` (e.g. `pick`, context `{choice}`) |
| Form → reply | `TextField`, `ChoicePicker`, `DateTimeInput`, `Slider`, submit `Button` whose action context binds the fields |
| Approval card | `Card` with context text + `Row` of primary/borderless `Button` (`approve`/`deny`) |
| Image | `Image` (https URLs; host files later via `/api/fs/download`) |
| Table, key-value | custom `crew/v1` |
| Chart, map | custom `crew/v1`, phase 2 |

Out of scope for the MVP: arbitrary HTML/JS, `Modal`, `Video`/`AudioPlayer`, live-updating surfaces from background work. The `::preview` WKWebView is the escape hatch for "anything else"; defer it until a real use shows up, because it is a second renderer with its own security surface.

### Schema sketch (what the agent writes)

````markdown
Here's the plan for Saturday:

```a2ui
[
  {"version": "v0.9", "createSurface": {"surfaceId": "sat-plan",
    "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}},
  {"version": "v0.9", "updateDataModel": {"surfaceId": "sat-plan",
    "value": {"items": [{"title": "Buy flour", "done": false}, {"title": "Book table", "done": true}]}}},
  {"version": "v0.9", "updateComponents": {"surfaceId": "sat-plan", "components": [
    {"id": "root", "component": "Card", "child": "col"},
    {"id": "col", "component": "Column", "children": ["title", "list", "save"]},
    {"id": "title", "component": "Text", "text": "Saturday", "variant": "h3"},
    {"id": "list", "component": "List",
      "children": {"path": "/items", "componentId": "row"}},
    {"id": "row", "component": "CheckBox", "label": {"path": "title"}, "value": {"path": "done"}},
    {"id": "save-label", "component": "Text", "text": "Save"},
    {"id": "save", "component": "Button", "child": "save-label", "variant": "primary",
      "action": {"event": {"name": "save", "context": {"items": {"path": "/items"}}}}}
  ]}}
]
```
````

Field names follow the [v0.9 spec](https://a2ui.org/specification/v0.9-a2ui/) (envelope keys `createSurface`, `updateComponents`, `updateDataModel`, `deleteSurface`; one component with id `root`; relative paths inside templates). Exact action and template syntax should be copied from the basic catalog JSON when writing the agent instructions, not from this sketch. A `crew/v1` component adds a second `catalogId` (e.g. `https://crew.gustaf.dev/catalogs/crew/v1.json`; it only has to be a stable string).

Versioning: Crew accepts `version` `v0.9`/`v0.9.1` now and `v1.0` once final; the renderer refuses unknown catalogs and components, which become the "couldn't display" chip.

## 5. How the agent learns it

- **Per profile, not per client.** Put the recipe in the bot's Instructions (`agent.system_prompt` overlay, which Crew already edits) or a `crew-ui` skill. A plugin `register_system_prompt_section` would apply to every profile on the host. All clients of that bot then see the fences, so the recipe must say: always write one or two lines of prose first, put the block last, and never rely on the block alone for information.
- Content: when to use a surface (choices, lists to tick, forms, structured comparisons; not for plain answers), the MVP component list with one example each, the action reply format (`<a2ui-action>` hidden turns: update the same `surfaceId`, don't repeat the whole card in prose), size limits.
- Generation help exists upstream: the A2UI Python SDK's prompt generator and the compact "Express" signatures (`conformance/test_data/skills/express_basic_catalog.skill.md` in the a2ui repo) can produce the catalog section; prune it to the MVP components to save tokens.

## 6. Open questions

1. **Cross-client noise.** Decided: opt-in per bot. A "Rich UI" toggle in the inspector installs (or upgrades) and enables the `crew-ui` skill on that bot only; Off disables it, so bots without it never emit fences into Hermex or Desktop. Approved for after the first release, with A2UI and the official SwiftUI renderer as in section 4.
2. **Reliability of model-written JSON.** If fences come out invalid often, move to path (a): a `crew-ui` plugin `render_ui` tool that validates server-side with the A2UI SDK and returns errors. That needs a host plugin install (by Gustaf, never by an agent).
3. **v0.9.1 vs v1.0.** The Swift package supports both; v1.0 is RC until Q4 2026. Start on v0.9.1 and move when v1.0 is final?
4. **Pinning.** No Swift release tags in a2ui-project/a2ui; pin a commit and bump deliberately. Verify it builds under Crew's Swift 6 / default MainActor settings before committing to it (the package compiles as its own module, so likely fine).
5. **Escape hatch.** Is `::preview` HTML worth a WKWebView at all, given its files live on the host and can disappear from history? Defer until there is a concrete chart/map the custom catalog can't cover.
6. **Images and files.** Should `Image` URLs that point at host paths load through `/api/fs/download` with the session's auth, like attachments?

## Sources

- Hermes Agent (local checkout): `tui_gateway/contracts/server_requests.py`, `tui_gateway/server.py:1444-1568`, `tui_gateway/tool_progress.py:276-362`, `tui_gateway/contracts/prompt_voice.py:26-40`, `agent/prompt_builder.py:726-757`, `agent/system_prompt.py:55-450`, `tools/desktop_ui.py`, `tools/preview_tool.py`, `tools/setup_choose_tool.py`, `tools/mcp_tool_content.py`, `hermes_cli/plugins.py:109-1087`, `apps/desktop/src/components/assistant-ui/{inline-preview-directive,transcript-directive,artifact-card}.tsx`, `apps/desktop/src/lib/transcript-directives.ts`, `apps/desktop/src/components/assistant-ui/embeds/registry.tsx`.
- A2UI: [repo](https://github.com/a2ui-project/a2ui) ([Swift](https://github.com/a2ui-project/a2ui/tree/main/swift), [Python agent SDK](https://github.com/a2ui-project/a2ui/tree/main/python/a2ui_agent)), [v0.9 spec](https://a2ui.org/specification/v0.9-a2ui/), [roadmap](https://a2ui.org/roadmap/), [community renderers](https://a2ui.org/ecosystem/renderers/), [BBC6BAE9/a2ui-swift](https://github.com/BBC6BAE9/a2ui-swift), [vpm238/a2ui-swiftui](https://github.com/vpm238/a2ui-swiftui), [Discussion #834](https://github.com/google/A2UI/discussions/834).
- MCP Apps: [SEP-1865](https://modelcontextprotocol.io/seps/1865-mcp-apps-interactive-user-interfaces-for-mcp), [overview](https://modelcontextprotocol.io/extensions/apps/overview), [ext-apps](https://github.com/modelcontextprotocol/ext-apps), [MCP-UI](https://github.com/MCP-UI-Org/mcp-ui).
- Others: [Adaptive Cards rendering](https://learn.microsoft.com/en-us/adaptive-cards/rendering-cards/getting-started), [AdaptiveCardUI](https://swiftpackageregistry.com/gonzalezreal/AdaptiveCardUI), [AG-UI](https://docs.copilotkit.ai/ag-ui), [ag-ui-swift](https://swiftpackageindex.com/paduh/ag-ui-swift), [Open-JSON-UI](https://docs.copilotkit.ai/generative-ui-specs/open-json-ui), [json-render (InfoQ)](https://infoq.com/news/2026/03/vercel-json-render), [Generative UI for Swift survey](https://uzori.ai/blog/generative-ui-swift-not-react).
