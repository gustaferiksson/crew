# Chat in its own window (macOS)

Like Messages on the Mac: double-clicking a bot in the sidebar opens that bot's chat in a window of its own, and the main window keeps its selection and stays usable next to it. iPhone and iPad are unchanged.

## Opening

- **Double-click** (or Return on the selected row) on a bot row in any section, the flat filtered list or search's Conversations section, or a double-click on a favourite tile. The first click selects it in the main window as today, the second opens its window. Opening a bot whose window is already open brings that window to the front instead of opening a second one (one window per bot: `WindowGroup(for: Bot.ID)` plus `openWindow(value:)`, which focuses an existing window with the same value). Rows use `contextMenu(forSelectionType:menu:primaryAction:)`, the List idiom for double-click; its primary action ignores group room ids and multi-selection. Tiles get their own double-click gesture, so a double-click selects once and opens once.
- **Context menu:** "Open in New Window" (`macwindow.badge.plus`) is the first item of a bot's row and tile menu, then a divider, then Pin and the rest. It stays enabled while offline, since opening a window needs no server (Pin, Move, Duplicate and Delete keep their offline disabling).
- **Menu bar:** File > Open in New Window (Cmd-O, like Mail's Open Message) acts on the main window's selected bot; disabled when nothing or a group room is selected.
- **Messages search hits** (the second search section) keep a single click selecting; a double-click does nothing more.
- The mention peek's card keeps opening the same window (#33), so all paths share one window per bot.
- Group rooms: not in this change (see Not in scope). A group row has no "Open in New Window" item and a double-click only selects it.

## The window

- The same `ChatScreen` as the main window's detail column: persona pill centred in the toolbar, transcript, composer, approval, question and payment cards, shop offer, offline line. The pill opens that bot's inspector as a trailing `.inspector` column inside the window (as #33 built it); opening it in a narrow window widens the window like Messages' Info panel (SwiftUI's inspector behaviour, rendered). The window's `ModelSwitcher` now loads that bot's models (today it never loads, so the pill's Model submenu and the inspector's Model row are empty), and both the window's and the main window's switchers reload when the bot's model changes in the roster, so changing it in one window updates the other.
- Title: the bot's title (`ChatView`'s `navigationTitle`, hidden in the title bar by `toolbar(removing: .title)`), so the Window menu, Mission Control and Cmd-` list it by name; it follows a rename. The main window lists as "Crew".
- Size: `defaultSize` 560 x 640 as today, no fixed minimum height and no `windowResizability` change, so the window min height work in #60/#10 applies to it unchanged. Frames come from SwiftUI.
- No sidebar and no New Bot button: one conversation, like a Messages conversation window. The chat window group adds no File > New item (`commandsRemoved()`), so there is no way to open an empty chat window.

## The main window

- On macOS the main scene becomes a single `Window("Crew", id: "main")`, like Messages: it is always listed in the Window menu, closing it leaves chat windows open, and Window > Crew (or a notification tap) reopens or focuses it with `openWindow(id: "main")`. File > New Window, which opened a second sidebar that polled the roster twice, goes away. iPhone and iPad keep their `WindowGroup`.

## One chat, two places

Both windows render the same objects:

- **Transcript, live work, cards:** one `ChatSession` per bot in `ChatSessions`. A streaming reply, the compact work log, Stop, steer and queue bubbles, approvals, questions and Hold to Pay show in both windows at once; answering in one removes the card in the other.
- **Draft:** `ChatDrafts` keyed by bot id. Typing in one composer shows in the other; sending from either clears both; the attachment tray is shared the same way. Text that Stop or a refused steer puts back lands in the draft once: the first window's handler empties `session.returned` before the second reads it.
- **Per window:** a dismissed shop offer, the Add Shop sheet and the 2 s offline delay are each window's own view state (the offer stays dismissed only where it was dismissed).
- **Unread:** an open chat window marks the bot seen whenever its position moves (`ChatScreen` already does), so the sidebar dot and tile badge clear while the window is open, whatever the main window has selected. Same rule as the main window's selected chat today, which also marks seen when it is behind another window or app (a known trade-off: a reply can arrive as a banner without leaving the dot; recorded in PLAN).
- **Sidebar row while its window is open:** preview, time and Working/Waiting/Failed update live as today. The red "Draft:" line shows for every chat that is not the main window's selection, also when that chat's own window is open (Messages shows "Draft" for any conversation not shown in that window).
- **Push:** a banner is hidden only while Crew is active and its key window shows that bot. Each window reports its bot to `PushCenter.show` whenever it becomes key (`appearsActive`): the main window its selection (and on every selection change, as today), a chat window its bot. That also clears the bot's delivered notifications, like selecting it.
- **Notification tap:** if that bot's chat window is open, it comes to the front (Messages focuses the conversation's window); otherwise the main window opens or comes to the front and selects the bot, as today. A payment tap still primes `expectPayment` in both cases. With no window open at all the tap is acted on when a window next appears (unchanged from today).
- **Inspector:** the main window's inspector belongs to its selection and the chat window's to its bot. Both edit the same profile through `ProfileDraft` autosave; the other window picks the change up through the roster reload.

## App work that outlives the main window

Today the network monitor, roster and room polling, push authorization and registration, read announcements, open-chat sync, local notifications, the foreground flag and stale-payment cleanup, sign-out resets and the notification route all run on the main window's views. With chat windows that is wrong two ways: closing the main window stops them while chat windows stay open, and a relaunch that restores only chat windows never starts them. They move into one `AppTasks` modifier that every window (main and chat, iPhone and iPad included) carries but only one runs: the first window to appear claims it, and when that window closes another open window claims it at once. Snapshot mode keeps them off as today. iPad's second window no longer runs a second set either. With no window open at all they stop, as they do today when the main window closes.

## Closing and restoring

- Cmd-W or the close button closes only that window. The bot's `ChatSession` keeps running (as for any opened bot), the draft stays, and the main window is unaffected.
- Closing the main window while chat windows stay open: they keep working (live events, roster, statuses, push); Window > Crew brings it back.
- Quit and relaunch: SwiftUI restores the main window and every open chat window with its bot id. A restored chat window shows the cached roster's bot at once (readable offline, composer in its offline state) and goes live once connected.
- Relaunch with only chat windows restored: they connect, load the roster and work without a main window.

## States

- **Loading** (no cached roster and not loaded yet): centred `ProgressView`.
- **Offline / unreachable:** the composer's offline line after 2 s, as in the main window; the transcript stays readable.
- **Signed out** (Sign Out, an expired session or an identity change): every chat window closes itself, since `Bot.ID` is the profile name and the next sign-in may be another server whose `default` is a different bot. A relaunch while signed out closes restored chat windows the same way. A closing chat window first opens or focuses the main window (`openWindow(id: "main")`), so `LoginView` always shows, also when only chat windows were open.
- **Bot deleted** (here or elsewhere, roster loaded and the id gone): "No Bot / This bot is no longer on the server." as today; Cmd-W closes it.
- **Long content:** same transcript and composer as the main window; the default width is above the chat column's 320 pt minimum.
- **Light and dark:** system materials, rendered both ways.

## iPhone and iPad

Unchanged UI: the double-click handling, the menu item and the menu bar command are `#if os(macOS)`, and the main scene stays a `WindowGroup`. The only shared change is the `AppTasks` owner, which keeps one set of app tasks running.

## Tests

- **macOS UI test** (new `CrewMacUITests` target, ad hoc signed, run only in CI on the GitHub-hosted xcode-27 runner, never on the user's Mac): launches the `layout` fixture with `-uiTest YES`, which keeps the regular activation policy and skips the capture, plus `-ApplePersistenceIgnoreState YES`. Double-clicks a bot row and expects a second window titled with the bot; double-clicks it again and still sees two windows; uses the context menu's "Open in New Window" on another bot for a third; types a draft in the selected bot's chat window and sees it in the main window's composer; Cmd-W closes the focused chat window. A fixture flag that signs the fixture connection out while a chat window is open checks that the chat window closes and the main window shows the sign-in screen.
- **Unit tests** (`CrewTests`): the `AppTasks` claim and hand-over (first claimer owns, a second claim is refused, release lets the next window claim).
- **Renders** (`-snapshot chat-window`, the real `BotChatWindow` as the window root): the chat, the chat with its inspector open (Model row), loading and No Bot, light and dark.

## Not in scope

- Group rooms in their own window: `GroupSession` lives per screen, so two windows of one room would poll and answer approvals separately. Needs a shared session per room first; follow-up.
- App work with no window open at all (unchanged from today).
- A "Show in Main Window" command in the chat window, dragging a row out to make a window.
