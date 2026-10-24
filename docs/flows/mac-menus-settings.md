# Menu bar commands and a Settings window (macOS)

An audit against the HIG found Mac actions that live only in the toolbar: New Bot and New Group (the New Chat button), Notifications…, Sign Out, the version line, Check for Updates (also in the app menu) and showing the inspector (the persona pill). The HIG is explicit: "Every toolbar item must also exist as a menu bar command. People can hide or customize the toolbar; it can't be the only place a command lives" (toolbars, macOS), and app options belong in a Settings window opened from the app menu with Command-Comma, never behind a toolbar button (settings, macOS). This change gives every Mac toolbar action a menu bar command and moves the Account menu's contents to their Apple homes, then removes that menu on the Mac. iPhone and iPad are unchanged.

## What Apple does

- **Messages:** File > New Message (Command-N) opens the new conversation in the main window, also when a conversation window is in front. View > Show Sidebar (Control-Command-S). Messages > Settings… (Command-Comma) is a toolbar-tabbed window (General, iMessage, …); the iMessage pane holds the Apple Account and its Sign Out button, which asks to confirm. No account or settings button in the main toolbar.
- **Mail:** File > New Message (Command-N) works from any window. Mail > Settings… has an Accounts pane for each account's details and removal. About Mail carries the version.
- **SwiftUI:** a `Settings` scene adds Settings… (Command-Comma) to the app menu and builds the toolbar-tabbed window from a `TabView`, titled with the selected pane. `SidebarCommands` adds View > Show/Hide Sidebar (Control-Command-S). `InspectorCommands` uses Control-Command-I for the inspector. The standard About panel shows the version and build from the bundle.

## Menu bar (every command, its shortcut and when it is enabled)

All commands are on the main `Window` scene's `.commands`, so they are in the menu bar whichever Crew window is in front. Items are never hidden, only disabled (the-menu-bar: "disable, don't hide").

### Crew (app menu)

| Item | Shortcut | Enabled |
| --- | --- | --- |
| About Crew | none | always. The standard panel: icon, "Crew", "Version 0.1.x (build)". This is where the version now lives. |
| Check for Updates… / Checking for Updates… / Downloading Update… / Install Crew x and Relaunch, then the status note | none | as today (`UpdateMenuItems`, `CommandGroup(after: .appInfo)`); unchanged. Debug builds show "This build doesn't update itself." |
| Settings… | Command-Comma | always, also signed out. Opens or focuses the Settings window. |

### File

`CommandGroup(replacing: .newItem)`, in this order:

| Item | Shortcut | Enabled |
| --- | --- | --- |
| New Bot… | Command-N | signed in and connected (`connection.state == .connected`), the same rule as the toolbar button. |
| New Group… | Shift-Command-N | connected and the server supports groups (`groups.isSupported`); visible but disabled otherwise. Messages has no group shortcut; Shift-Command-N is the Mac's "new item of the second kind" (Finder New Folder), and Crew has no other use for it. |
| Open in New Window | Command-O | unchanged: the main window's selected bot (`FocusedValues.selectedBot`); disabled when the main window is not in front, nothing is selected or a group room is selected. |

The ellipsis follows the HIG: New Bot and New Group open a sheet that needs more input. The toolbar menu's items keep their titles ("New Bot", "New Group"), as Messages' compose button is "New Message" without one.

**From any window:** New Bot and New Group bring the main window forward (or reopen it with `openWindow(id: "main")` if it was closed) and present the sheet there, like Messages' New Message from a conversation window and Mail's from any window. The command asks through `Scenes` (`newChat`, the app's cross-window state), and `BotsView` takes the request once on appear and on change, so the sheet shows in the main window even when it had to be reopened. If the main window is already presenting a sheet or alert (New Bot, New Group, a search hit's transcript, a delete confirmation, New Section, Something Went Wrong), the request is dropped and cleared, so it never fires later when that presentation closes. A sheet presented by a view inside the chat or inspector (an attachment picker, Add Shop, the avatar picker) is not visible to this check; SwiftUI then shows New Bot after that sheet closes (a known gap). A minimised main window is restored by `openWindow(id: "main")`.

### View

| Item | Shortcut | Enabled |
| --- | --- | --- |
| Show Sidebar / Hide Sidebar | Control-Command-S | `SidebarCommands()`: the main window's split view sidebar; disabled when the front window has no sidebar (a chat window, Settings, the sign-in screen). Its title follows the state. |
| Show Inspector / Hide Inspector | Control-Command-I | the front window's inspector. The main window publishes a focused binding to its `showsBot` only while a bot or group room is selected, a chat window only while its bot exists (not while the roster loads, not on "No Bot"); otherwise the value is nil and the item is disabled, also on the sign-in screen and in Settings. Title follows the state ("Hide Inspector" while it is open), as the HIG asks for show/hide items. It flips the same flag as the persona pill and the inspector's close button. |

Control-Command-I is SwiftUI's own shortcut for an in-window inspector (`InspectorCommands`); the HIG's Option-Command-I is for a separate inspector window, which Crew doesn't have. Crew uses its own command on a `FocusedValues` binding instead of `InspectorCommands` because the main window's inspector only shows with a selection: the system item would stay enabled with nothing selected and flip a hidden flag that then pops the inspector open on the next selection.

Enter Full Screen and Show Tab Bar stay as the system adds them. Toolbar customisation is not added (the Mac toolbar has two items).

### Window, Edit, Help

Unchanged. Window lists "Crew" and each chat window by bot name.

## Settings window

A `Settings` scene (Mac only), toolbar-tabbed, two panes:

| Pane | Icon | Content |
| --- | --- | --- |
| Account | `person.crop.circle` | the signed-in server and user, connection status, Sign Out… |
| Notifications | `bell.badge` | today's `NotificationSettings` form: status, Allow Banners and Sounds, Send Test Notification, the Notify Me About toggles and the footer, unchanged in content. |

- Window title is the selected pane's name (SwiftUI's `TabView` in `Settings`), the tabs are a fixed, always visible toolbar, minimise and zoom are dimmed (system Settings window), each pane is a grouped `Form` with a fixed 480 pt width and a fixed height that fits its content, so the window resizes to the pane when switching, as in Messages. The sheet's `minWidth 440, minHeight 480` frame goes away with the sheet.
- The last viewed pane is restored on the next open (HIG settings: "Restore the last-viewed pane"), kept as an app preference (`settingsPane`) like `pushPrefs`. Snapshot renders pick their pane without writing it; UI tests click the pane they need.
- Settings carries the app's stores and `AppTasks`, like every other window: while it is the only window open (main and chat windows closed), it keeps the network monitor and roster polling alive (so the Account status is live), routes a notification tap by opening the main window, and runs the sign-out reset. `AppTasks` hands ownership to the window that appeared last and back when it closes, as for chat windows.
- **Account pane, signed in:** a section with Server (host), User (the signed-in username) and Status: "Connected", "Connecting…" or "Can't reach server" with the same green, secondary and orange as the connection pill uses. A second section with a "Sign Out…" button. Sign Out asks first, like Messages: a confirmation "Sign out of hermes.example.com?" with "Crew forgets this session and the unsent drafts on this Mac, and closes its chat windows." and the buttons Sign Out (destructive) and Cancel. Confirming does what the toolbar's Sign Out did (unregister push, `connection.signOut()`, clear drafts; `AppTasks` resets chats and groups as today), then (after sign-out finished) brings the main window forward with the sign-in screen (`openWindow(id: "main")`, so it shows even if only Settings was open); a New Bot or New Group sheet open in the main window goes away with `BotsView`; chat windows close themselves as today (mac-chat-window spec). The Settings window stays open and switches to the signed-out state.
- **Account pane, signed out:** `ContentUnavailableView` "Not Signed In", `person.crop.circle.badge.xmark`, "Sign in from the Crew window." and a "Show Crew Window" button (`openWindow(id: "main")`). Signing in from the main window while it is open switches it to the signed-in pane live.
- **Notifications pane:** as the sheet today. Signed out: Status reads "Not signed in" (instead of an endless "Checking…"), the footer reads "Sign in to set up notifications.", Send Test is disabled (it already needs a connection); the Notify Me About toggles stay editable, since they are local preferences sent with the next registration. Offline or unreachable: Send Test disabled as today; status is the last registration's result, or "Can't reach server" when there was none this session (instead of "Checking…"). The signed-out and offline status lines are Mac only, so the iOS sheet reads exactly as today.
- Long content: the user name and host truncate in the middle at the pane width; the notifications footer wraps.

## Toolbar after the change (Mac)

- The Account menu is removed from the Mac sidebar toolbar, because every item has a proper home: Notifications… → Settings > Notifications, the version line → About Crew, Check for Updates → the app menu (already there), Sign Out → Settings > Account. The sidebar toolbar keeps only the system sidebar toggle; the search field stays at the top of the sidebar.
- The detail column keeps its New Chat button (New Bot / New Group menu when groups are supported, else a New Bot button), now backed by File > New Bot and New Group.
- The chat toolbar's persona pill keeps toggling the inspector, now backed by View > Show/Hide Inspector.

## Where Sign Out goes, and why

Settings > Account. The HIG files "account options" under the app's own settings area (settings: rarely changed, general options), not in the main toolbar ("Don't add Settings buttons to the main toolbar"). Crew has exactly one account (one server, one user), and signing out is rare and destructive (it drops drafts), so it belongs next to the account's details, as Messages puts Sign Out in its iMessage pane and Mail puts account removal in Accounts. Keeping a toolbar account menu just for Sign Out would leave a one-item menu that Apple's Mac apps don't have. No File or app-menu Sign Out item: Messages and Mail have none, and Shift-Command-Q is the system's log out.

## States

- **Signed out:** the main window shows the sign-in screen; New Bot, New Group, Open in New Window, Show Inspector and Show Sidebar are disabled; About, Check for Updates and Settings… work; Settings shows its signed-out Account pane.
- **Connecting, unreachable, offline:** New Bot and New Group disabled (as the toolbar button is); Open in New Window, Sidebar and Inspector toggles work (reading needs no server); Settings > Account shows the status.
- **Several windows:** the main window and any chat windows share the menu bar. New Bot and New Group always act on the main window. Sidebar and Inspector act on the front window. Open in New Window acts on the main window's selection and is disabled when a chat window or Settings is in front. Closing the main window keeps the commands (New Bot reopens it).
- **Only Settings open:** it owns the app tasks (see Settings window), so its status is live and notification taps open the main window.
- **No window open:** New Bot and New Group reopen the main window and show the sheet; Settings… opens Settings; the rest are disabled.
- **Connection drops while the New Bot sheet is open:** unchanged (the sheet's own Create handles it).
- **Light and dark:** system menus and the system Settings window; the panes are rendered both ways.

## iPhone and iPad

Unchanged. The Account toolbar menu (Notifications…, Check for Updates, the version, Sign Out without confirmation) and the Notifications sheet with its Done button stay exactly as they are; the menu bar commands and the Settings scene are macOS only. Shared code changes are limited to `NotificationSettings`, whose `NavigationStack` and Done button become iOS only (the Mac pane has no Done), and its signed-out status, which iOS never shows.

## Verification

- Mac UI test (`CrewMacUITests`, CI runner only): File > New Bot… and Command-N show the New Bot sheet, also from a chat window; View > Show Inspector opens the inspector and the item then reads Hide Inspector; Command-Comma opens Settings with the Account pane and Sign Out…; the main window's toolbar has no Account menu. They run on a CI runner in `ui.yml` after merge (Mac UI tests never run on the user's Mac, and dispatching `ui.yml` on a branch is not available here).
- Mac UI test: Settings > Account > Sign Out… with a chat window open leaves the main window on the sign-in screen and Settings on "Not Signed In", and closes the chat window.
- Unit test: the `Scenes` new-chat request is taken once, and a dropped request is cleared and does not fire later.
- Renders (`./snapshot.sh mac`): Mac `layout` (checked against main's: identical but for the removed Account button, not committed), `settings-account`, `settings-account-signed-out`, `settings-notifications` (captured from the real Settings window, which the fixture opens with `openSettings`), light and dark; iOS `notifications` unchanged.

## Not in scope

- Edit > Find (Command-F) to focus the sidebar search, as Messages has: the search field is in the sidebar, not the toolbar; a follow-up.
- A General pane: Crew has no general options yet.
- Group rooms in their own windows (unchanged from the chat window spec).
