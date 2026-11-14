# Active Now filter (#351)

Show only the bots that are doing something right now, like Hermes Desktop's Bots pane "Active now" filter.

## Rule

A bot is active when any of these holds (`ChatSessions.isActive(_:in:at:)`):

- Its row status is Working or Waiting (`ChatSessions.status`, so an open chat whose turn streams while the server still says `starting` counts too). Desktop only knows the focused chat's live turn; Crew already polls `session.active_list` for every bot, so every live turn counts.
- It wrote in the last 90 seconds, measured on the row's own time (`summary.time`: the last visible message, else the preview window, else `canonical_session.last_active`). Desktop reads `last_active`, which is a prompt-time heartbeat that never moves when a reply lands, so a reply would not count there.
- Its kanban/tool worker heartbeat (`worker_session.last_active`, already in `profiles.list`) is under 150 seconds old (workers beat every 60 s; Desktop's window).

A connected gateway alone, unread or failed never counts. A room is active when its `updated_at` is under 90 seconds old; its live "working" state exists only inside an open room, so it is not used (no new polling). The open chat or room always stays in the list while it is selected, like Mail's filtered mailbox keeps the open message.

Time passes without a state change, so the list rechecks every 5 seconds while the filter is on.

## Surfaces

- **iPhone:** Mail's filter: a toggle (`line.3.horizontal.decrease`, "Active Now") in the bottom bar, at the leading end of the search field's glass bar (`ToolbarItem(.bottomBar)` with `DefaultToolbarItem(kind: .search, placement: .bottomBar)`). Filled tint while on.
- **Mac:** the same toggle in the sidebar's toolbar beside the sidebar toggle, plus View > Show Only Active Bots / Show All Bots (Cmd-L, Mail's Enable Message Filter shortcut) on a `FocusedValues` binding, per the Mac menus decision. In the narrow sidebar strip the toggle and command are gone and the strip shows every bot, as it ignores search.
- **List while on:** one flat list without headers, like name search: favourites and section bots in their usual order, then rooms. Favourite tiles become rows. Rows are the normal bot rows, so they keep status, unread dot, preview, time, context menu and swipes.
- **Hidden bots:** never shown by the filter (Photos' Hidden album: activity never surfaces a hidden bot, `docs/flows/hide-bots.md`), and the Hidden section is gone while it is on.
- **Search:** typing a query shows the normal search results over every bot; the filter applies to the browsing list only and comes back when the query is cleared.
- **State:** `@State`, off at every launch (no `UserDefaults`, see CLAUDE.md).
- **Light/dark:** system list, toolbar and `ContentUnavailableView` colours, see renders.

## States

- Empty: `ContentUnavailableView` "No Active Bots", "Bots that are working or wrote in the last 90 seconds show here.", with a Show All Bots button that turns the filter off.
- No bots at all: the existing "No Bots" view wins. Loading: the spinner wins.
- Offline: the rule runs on the cached roster and last statuses, so it can show a stale Working bot until the next roster read; the toggle stays usable.
- Long content: rows truncate like every bot row.

## Verification

- Unit: `ActiveNowTests` replays `Tests/fixtures/scenarios/cold-open` (working bot active 10 minutes after it last wrote; a reply active at +60 s and +89 s, inactive at +120 s) and the recorded `worker_session` from `profiles.list.v0.21.7.json` (150 s window). All three fail against Desktop's plain `last_active < 90 s` rule.
- Renders: `sidebar` (off), `sidebar-active`, `sidebar-active-empty`, iOS and Mac, light and dark; checked in as `docs/flows/renders/active-now-*.png`. Mac: `-inspectorProbe "open,close,sidebar:250,sidebar:200,width:0,open,close"` survives (the toggle leaves with the strip).
