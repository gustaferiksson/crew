# Bot roles (work titles)

A bot can carry a short work title, its role on the crew: "Marlow, Chief of Staff". The user sets it in the inspector (or when creating a bot), and other agents can set it through the same API. It shows wherever telling bots apart helps and nowhere it would crowd a compact control. A bot with no role looks exactly as it does today.

## Storage

- `ui_meta["hermes-bots"].role`: a string, trimmed, absent when empty. One key in the namespace Hermes Desktop and Hermex already share, owned by Crew the way `expression` is owned by Hermex.
- Why there:
  - Hermes Desktop has no role or subtitle field. Its `BotMeta` (`apps/desktop/src/plugins/hermes-bots/types.ts`) has `title`, `description`, look keys, `pinned`, `hidden`, sections, `groups`, `created` and `screenAutoOpen`. Roster `title` is the bot's display name (`_bots_title`), not a role.
  - `hermes-bots.description` is not a role: Desktop's create dialog writes the whole description ("Mission") there, and Hermex shows it as a chip only when it is 24 characters or fewer. Crew's inspector Description is the profile's own `description` (a sentence or more), and the mention peek already reads both as About text.
  - `ui_meta["crew"]` holds the read marker (`{session, messages}`), which `markSeen` rewrites up to every 2 s under its own revision. A role there would be overwritten by the next read, or would need the marker writer to merge and handle conflicts it never sees today.
  - Inside `hermes-bots` it rides what already works: every Crew writer (inspector save, pin, sections, New Bot, Duplicate) sends the whole received object with unknown keys kept, and Desktop's `persistBotMetaPatch` writes `{...server, ...patch}` from a fresh read, so Desktop and Hermex edits keep it. One revision (`ui_meta_revisions["hermes-bots"]`) and the existing conflict handling cover it.
- Duplicate (Crew and Desktop) copies the role on purpose with the rest of the look (unlike `pinned`/`hidden`): a copy usually starts as the same kind of teammate, and the "(copy)" title tells them apart until renamed.
- No length cap on the server (only the 64 KB namespace cap); Crew's surfaces truncate. A role is meant to be a few words. `Bot.role` trims it and turns line breaks into spaces, so a multi-line value written by an agent still reads as one line; blank means no role.
- Hermex shows a short `hermes-bots.description` (24 characters or fewer) as a role chip. Crew does not fall back to it: "no role" must look exactly like today, and a description is not a title. Whether Crew should adopt that fallback is a product question for the user.

## Setting it from an agent

`ui_meta` is written only by the gateway's `profiles.configure` (no CLI or REST route writes it on 0.21.7). Two paths:

**A. Through the gateway (preferred).** Any script or agent that holds dashboard credentials (password login, then `POST /api/auth/ws-ticket` and the `/api/ws` socket, exactly what Crew and `Tests/bot_probe` do) makes the same two calls Crew makes:

1. `profiles.list {}`: take the target row's `ui_meta["hermes-bots"]` (or `{}`) and `ui_meta_revisions["hermes-bots"]` (missing means 0).
2. `profiles.configure {name: "<profile>", ui_meta: {"hermes-bots": {...received object, "role": "Chief of Staff"}}, ui_meta_expected_revisions: {"hermes-bots": <revision>}}`.
3. If `applied.ui_meta_conflicts` comes back, read again and retry (Desktop and Crew retry 3 times). Always send the whole received object: the server replaces it, so a partial object drops the title, look and pin.

Clearing: send `"role": null` inside the object. The server stores the null and every client reads it as no role. Leaving the key out also clears it for Crew, but Hermes Desktop merges server meta into its local cache as `{...local, ...server}`, so a vanished key can survive there and come back on a Desktop Duplicate. Crew itself clears by omitting the key (its encoder drops nil), a known gap on that Desktop path only.

**B. On the server host, without dashboard credentials.** A bot that only has its terminal tools (a chief of staff living on the same Hermes host) can edit the target's `profiles/<name>/profile.yaml`: set `ui_meta.hermes-bots.role` and add 1 to `_ui_meta_revisions.hermes-bots` in the same write, so a client holding the old revision gets a conflict instead of silently overwriting it. The roster cache is keyed on the file's mtime, so `profiles.list` shows the change on the next poll. This bypasses the gateway's lock, so do it only while no client is saving that bot.

Other clients pick a change up on their next `profiles.list` poll (Crew: within 2 s).

## Editing

- **Inspector (Info, both platforms):** a Role field directly under the name, like the job title under a name in Contacts: centred, `.body`, secondary colour, prompt "Add Role", single line, the same plain text field style as the name (quaternary fill while focused). Return in Name moves to Role (`.submitLabel(.next)`); Return in Role or focus loss ends editing. Disabled until the draft has loaded, like the name.
- **Draft model:** the role is `ProfileDraft.Identity.role` (prefilled from `Bot.role`), so it rides the identity rules that exist: an identity change sends `hermes-bots`, a reload keeps unsaved identity edits, a conflict reloads the identity. `outgoingMeta` writes `role` only when it differs from the baseline, like the title; whitespace only saves as no role.
- **Autosave:** the same 0.6 s debounce as the name. `BotInspector`'s `onChange(of: draft.fields)` must count the role as typed text (`typed.identity.role = new.identity.role`), otherwise every keystroke saves at once. Saving…/Saved and failure with Try Again show in the status line under it; the failure label reads "name, role and look".
- **Conflict:** a stale revision reloads name, role and look, and the notice reads "This bot's name, role or look changed on another device. Crew loaded the latest version, so make those changes again."
- **Changed elsewhere while the inspector is open:** today the draft only reloads on (re)connect, so a role set by an agent would stay stale in the field and the next rename would hit a conflict. New: when the roster brings a new `hermes-bots` revision for the open bot and the identity has no unsaved edits, the draft adopts the roster's meta, revision and identity (name, role, look) at once. With unsaved edits it keeps them, and the save conflicts as today.
- **New Bot sheet:** a Role field in the Name section under Display Title (prompt "Role", like the Display Title row; an example prompt read as a value), written in the same single `hermes-bots` write as the title and look; the header preview shows it under the title.
- After a save the inspector reloads the roster, so the list, tiles and peek follow at once.

## Display

- **Bot list row (iPhone, iPad, Mac):** the name line reads "Marlow · Chief of Staff": the name in the row's headline style, then " · " and the role in `.subheadline` regular, secondary colour (the trailing time's size; Mail and Phone keep secondary information smaller). Name and role are one concatenated `Text`, so tail truncation drops the role first, then the name. The trailing label (time, Working, Waiting, Failed) is `fixedSize`, so it never truncates. The two-line preview is untouched, so rows keep their height, matching group rows and today's rows. Why not a third line: every row with a role would grow, and Messages and Slack keep the list to name, preview and time; inline reads like Slack's "name · title" without adding height.
- **Favourite tile:** the name, then the role on the line under it in `.caption2` regular, secondary, both one line and tail-truncated to the tile width (about 70 pt at the Mac's 240 pt sidebar minimum, so long roles truncate there). That second line is the one that shows "Working" or "Waiting" today (`.caption2` medium, coloured): while a bot works or waits, the status replaces the role (status matters more in the moment) without animation, as the status line switches today. With no role and no status it stays the blank line it is today, so every tile keeps the same height.
- **Search:** results use the same `BotRow`, so they show the role; the role also matches the query ("chief" finds Marlow), like Desktop's roster filter, in both the one-character filter and the Conversations section. Message hits keep name, time and snippet (the snippet is the point there).
- **Mention peek:** the role on its own line under the title, `.subheadline` secondary, above the `@handle` and status line, like a contact card's subtitle. Long roles wrap to two lines at most.
- **Group inspector member rows:** the role as a `.subheadline` secondary line under the member's name, like a Slack channel's member list, since a room is where telling members apart matters.
- **Inspector header:** the role field itself shows it.
- **Skipped:**
  - Chat header pill: compact capsule centred in the toolbar, shared with group rooms and narrow on iPhone; Messages shows the name only. The role is one tap away in the inspector.
  - Composer @ picker rows ("Scout @scout"): the handle is what gets typed; the role would make eight rows heavier while typing. @ matching stays on handle and title, since a token must be one of those.
  - Bubble mention tags, group speaker labels, agent-message sender labels ("Message from <sender>"), the peek's "Message to"/"reply" section titles, push titles (set by crew-push from the title) and the Mac chat window title: unchanged.

## Every direction

- **Set in Crew, read elsewhere:** another Crew device shows it within 2 s; Desktop and Hermex keep the key on their own saves and don't draw it.
- **Set by an agent or another client:** Crew shows it on the next roster read (2 s poll), including an open inspector without unsaved name, role or look edits.
- **Cleared:** every surface is back to today's look.

## States

- **Empty role:** no " · ", no extra line, tiles keep their blank line: identical to today.
- **Long role or long name:** row truncates the role first, then the name, with an ellipsis, never wrapping and never squeezing the time; tile truncates each line on its own; peek wraps the role to 2 lines.
- **Offline or disconnected:** like the name, the field stays editable once the draft has loaded; a save attempted offline fails with the inline notice, Try Again waits for the connection, and the reconnect load saves the dirty fields. Before the first load the field is disabled. Cached rows keep showing the role from `bots.json`.
- **Save failure:** inline notice with Try Again; the typed role stays in the field.
- **Dynamic Type:** rows and tiles stay one line per field and truncate; the peek wraps.
- **Light and dark:** system secondary styles only.
- **Accessibility:** the row's name line is labelled "Marlow, Chief of Staff" (no "middle dot"); the tile is one element labelled with the name and role, its status ("Working", "Waiting") as the value, so a busy tile still speaks the role; the Role field is labelled "Role".

## Tests

- `CrewTests`: `BotMeta` decodes and re-encodes `role` next to an unknown key; a cleared role encodes no key; `Bot.role` is nil for blank and one line for multi-line; `ProfileDraft` prefills the role and isn't dirty; its outgoing `hermes-bots` object carries the edited role, drops it when cleared and keeps other keys; adopting a newer roster revision takes the new role, and doesn't with unsaved edits.
- UI test (iPhone simulator): the sidebar fixture row's name line reads "Forge, Release Engineer"; searching "release" lists Forge.
- Renders (private iOS simulator, light and dark): the sidebar with roles in rows and a pinned tile with a long name and role; the inspector Info header with the Role field; the New Bot sheet. Fixture bots get roles (some left empty). macOS is not rendered: its snapshot path launches the Mac app, and this change must not drive Mac windows or touch the app's defaults domain; the views are shared SwiftUI and the Mac tile width is covered by truncation.
- Real server, `crew-test` only, path A: set a role through `ProfileDraft` (the inspector's save) and read it back from `profiles.list` with the other `hermes-bots` keys intact, set and clear it with a raw `profiles.configure` like an agent would, then restore the original object.

## Docs

- `docs/hermes-api.md`: `role` (Crew-owned) in the `hermes-bots` key list; the `crew` read marker described as `{session, messages}`.
- `docs/PLAN.md`: a Decisions line for bot roles; the search line and the Navigation row anatomy mention the role.

## Not in scope

- Showing the role in Hermes Desktop or Hermex (their code).
- Using the role in prompts (the mention identification note keeps title and handle).
