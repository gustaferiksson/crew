# Connection gallery: names, symbols and categories for Hermes' catalog (#346)

Add Connection lists Hermes' own catalog (`GET /api/mcp/catalog`, 66 remote servers on 0.23.1, 56 OAuth and 10 without sign-in, recorded in `Tests/fixtures/mcp/catalog.v0.23.1.json`) as bare config names with monogram tiles. This turns it into a gallery: a small overlay bundled in Crew, keyed by the catalog `name`, gives each entry a display name, a category and an SF Symbol; the sheet groups by category and searches. Three vendors Hermes doesn't list join from the same overlay: GitHub (personal access token) and Zapier and Granola (OAuth with dynamic client registration). Vendors that need a pre-registered OAuth client (HubSpot, Box, Slack, Asana v2, GitHub OAuth) wait for #325. The official MCP Registry is not used: 38k remote entries with no auth metadata or quality signal.

## Settled constraints

- **Hermes' catalog stays the backbone.** It is curated, live-verified, and carries tool filters and per-vendor OAuth quirks; installing still sends `POST /api/mcp/catalog/install {name, env}`. The overlay only presents it.
- **The raw name stays the identifier.** Every request, the server's `config.yaml` key and the bot's `.env` variable keep using it. The overlay is display only.
- **No third-party logos or trademarks are bundled.** Each entry gets an SF Symbol (generic glyphs only, none of Apple's product symbols) in a tile tinted by its category, the same 28 pt rounded tile as today's monogram.
- **Unknown names still show.** A catalog entry the overlay lacks (a newer Hermes, a custom catalog) shows its raw name, its monogram tile and its description under **Other**, last. Nothing is hidden because Crew doesn't know it.
- **Overlay is a Swift table** (`Sources/Inspector/ConnectionGallery.swift`), not a JSON resource: no bundle plumbing and no decode failure path. A unit test checks it covers every name in the recorded catalog and that every symbol exists. GitHub's look also carries its token page.
- **Extras are catalog-shaped entries in the same file** (`connectionExtras`): name, description, URL and sign-in kind (`header` for GitHub, `oauth` for Zapier and Granola), no setup notes or required fields.
- **PLAN.md:** the first sentence of the "Connection names show exactly as configured" line becomes the overlay rule, and a "Connection gallery (#346)" line joins the Connections decisions.

## Categories (fixed order)

Productivity, Developer Tools, Data & Monitoring, Business & Finance, Design & Media, Reference, Travel & Lifestyle, Other. Each has its own tile tint. Rows inside a category sort by display name (`localizedStandardCompare`).

## Add Connection sheet (iPhone and Mac)

Same container as today: a sheet presented from `BotInspector`'s Form, `NavigationStack`, title "Add Connection", Cancel; iPhone inline title with `.searchable`, Mac 420 x 560 pt with the search field as the Form's first row (PLAN.md's Mac sheet rule).

1. **Custom Connection** row first, unchanged.
2. One **Section per non-empty category**, header the category name. A row: tile (symbol or monogram), display name (one line), the catalog description (subheadline, secondary, two lines), "Added" trailing and the row disabled when the bot already has it (catalog `installed`; for the three extras, the bot's server list holds that name).
3. **Extras** (GitHub, Zapier, Granola) sit in their category beside Hermes' entries, marked by nothing: the user doesn't care where an entry comes from. If Hermes' catalog ever lists the same name, the catalog entry wins and the extra is dropped.
4. **Search** matches display name, raw name, description and category name ("travel", "finance"); results stay grouped, empty categories hide. No match: an empty Section whose header reads "No Results for "query"" (PLAN.md's empty-state-in-Form rule). Custom Connection stays visible while searching, as the way out.
5. **Loading:** small spinner in place of the categories. **Couldn't load** (catalog request failed): "Couldn't load the catalog." with Try Again, as today; the extras don't list on their own then, so the sheet never shows a three-entry catalog that looks complete. **Offline:** the Add Connection… button is already disabled offline; if the connection drops with the sheet open, Add in a detail page is disabled (unchanged).

## Detail page (pushed in the sheet)

Header: tile and display name; navigation title the display name. Then the catalog description, the Address (selectable, middle truncation), and how it signs in.

- **Hermes entry:** unchanged (required fields, setup notes, "After adding it, sign in from the Connections list." or "No sign-in needed.").
- **Zapier, Granola:** Address `https://mcp.zapier.com/api/v1/connect` / `https://mcp.granola.ai/mcp`, footer "After adding it, sign in from the Connections list." Add sends `POST /api/mcp/servers {name, url, auth: "oauth"}` (the Custom Connection write). After adding, the row reads Needs Sign-In and the existing Sign In flow (`/auth`, `webAuthenticationSession`, polling) runs; Hermes registers its client with the vendor through DCR.
- **GitHub:** Address `https://api.githubcopilot.com/mcp/` with the footer "Sent as a bearer token. Hermes keeps it in the bot's secrets.", then an **API Key** secure field whose prompt reads "Personal Access Token" (the same term as the Connection page's Sign-In: API Key and Change API Key), a **Create a Token on GitHub** link and the footer "Choose the repositories and permissions it may use, such as Contents, Issues and Pull requests." (a fine-grained token defaults to public repositories, read-only). The link (`https://github.com/settings/personal-access-tokens/new`) is a SwiftUI `Link`, so it routes like every other web link: the GitHub app when installed (unverified whether the app can create tokens; the page also works in Safari) or the in-app browser on iPhone, the default browser on Mac; GitHub asks for a login first when signed out. Add is disabled until the field has text. Add sends `POST /api/mcp/servers {name: "github", url, auth: "header", bearer_token}`, the Custom Connection API Key write: Hermes stores the token in the bot's `.env` as `MCP_GITHUB_API_KEY` and writes `Authorization: Bearer ${MCP_GITHUB_API_KEY}` into `config.yaml`, never the token itself. The Connection page's Change API Key already rotates this shape. A wrong token shows on the row as the red error Hermes' `/test` returns.
- Errors on Add show Hermes' `detail` in red in the form (unchanged); the sheet closes on success and the list reloads and tests the new server.

## Display names elsewhere

The Connections rows (tile, name, remove confirmation) and the Connection page (header, navigation title, remove confirmation) show the overlay's display name and tile when the configured name is an overlay key, else the raw name and monogram as today. The page's Details gain a **Name** row with the raw name when it differs, because Hermes' own errors ("Server 'linear' already exists"), `config.yaml` and the bot's tool names use it. A hand-made server called `linear` shows as Linear.

Follow-up, not in this change: the remaining strings that name a connection (Change Address and Change API Key messages, the "headers were written by hand" error, Add to Other Bots' footer and outcomes, New Bot Advanced's list and its Bot Created alert) still show the raw name.

## Not touched

Chats, the bot list (preview, time, status, unread), push and the Mac menus show no connection names. Rooms, cards and routines are unaffected.

## States checklist

- Light and dark: system Form styling; tile tints are system colors with the existing gradient, white glyphs.
- Long content: display names one line, descriptions two lines, addresses middle-truncated; the inspector's 280 pt minimum column is unchanged (the sheet has its own width).
- VoiceOver: the tile is hidden; the row reads display name, description, Added.
- Dynamic Type: rows grow; tiles keep 28 pt like the monogram (they sit beside text, as in Settings).

## Verification

- Unit: the overlay covers every name in `catalog.v0.23.1.json`; every symbol resolves; grouping puts an unknown name under Other with its raw name; extras are dropped on a name collision and show Added from the server list; search over display name, raw name and description; the GitHub and extra bodies equal the Custom Connection writes.
- Real server (`Tests/connection_probe/run.sh gallery`, throwaway `crew-test-gallery` bot, deleted after): GitHub with a fake token stores a `${MCP_GITHUB_API_KEY}` reference and no token text in the raw config, the key `is_set` in `.env`, the server listed; Zapier and Granola add and `/auth` answers `authorization_required` with an authorization URL (the URL is never printed), and the flows are cancelled.
- Renders, iPhone and Mac, each light and dark: `add-connection` (an unknown `acme-notes` entry in the fixture), `github-connection` (the GitHub detail page), `inspector-connections` (overlay names beside raw `files`) and `connection-page` (display name title, Name row).
- Not verified: a completed Zapier or Granola vendor login, and a live GitHub token.
