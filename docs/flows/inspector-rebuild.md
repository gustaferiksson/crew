# Bot inspector on the system grouped form

The bot inspector (iPhone and iPad pushed bot page, Mac inspector column in the main window and in a chat window) and the group inspector are rebuilt on the system grouped `Form`, like Contacts' contact card and Messages' conversation details on iOS and the grouped Form inspectors of macOS 27 apps. The user asked for it ("Yes, follow iMessage/Apple as close as possible"). Behaviour and data flow do not change: every field, button, sheet, confirmation, Hermes call, save, error and offline rule stays as it is today; only the containers and controls that draw them change, plus the one header change listed under Loading.

## What Apple does

Contacts and Messages' details put a centred identity header (large avatar, name, subtitle, action buttons) on the grouped background with no card behind it, then system inset-grouped sections with a header above and a footer below each group. Rows are system rows: a tap highlights the whole row; a row that pushes shows the system chevron; a row that opens a sheet or runs an action is a button row with no chevron; destructive actions are red button rows in their own section ("Delete Contact"), always confirmed. Lists of removable things offer swipe actions and a context menu (Mail, Reminders, Passwords). A small fixed set of views on one page switches with a segmented control (Calendar, Health). On the Mac, inspectors use a grouped `Form` in the column (label on the left, value or control on the right, push buttons for actions) and right-click menus for row actions.

## Shell

- `BotInspector.body` is one `Form` with `.formStyle(.grouped)` on both platforms, so the system draws the grouped background, section insets, separators, row highlight and scrolling. The hand-built `Card` (fill plus 16 pt radius), the `VStack` in a `ScrollView`, the manual `Divider`s between rows and the 16 pt page padding go away.
- Order: identity header section, the tab picker, then the selected tab's sections.
- Mac keeps the locked lines: the `.inspector` column width (`inspectorWidth`, min 280 / ideal 340 / max 480) and the xmark `ToolbarItem(placement: .cancellationAction)` shown only while `isPresented`. `.contentMargins(.bottom, 24, for: .scrollIndicators)` stays. iOS keeps `.navigationBarTitleDisplayMode(.inline)` with no title, as Contacts' card does. `.defaultScrollAnchor(Snapshot.scrollsToBottom …)` stays on the Form (renders use it to show the bottom).
- Sheets, confirmation dialogs, alerts and `.task`s that today hang off a card's `VStack` attach to a section or row inside the Form (the render confirms they do not split a section). The Passwords tab's vault load stays keyed on the gateway and connection state as today.
- Nothing pushes from the inspector. On iOS the inspector is itself pushed with `navigationDestination`, and a push over it would fire its `onDisappear` save and restart its load, routine, conversation and vault tasks; so every row that opens something opens a sheet, as today, on both platforms.

## Row looks

- **Rows that open something** (Capabilities, Other Conversations and editable logins open a sheet; group members switch to that bot's chat): on iOS a full-row `Button` with the system highlight and the label in primary and secondary colours (not accent-tinted), no chevron, as Settings does for rows that present modally. On the Mac `.buttonStyle(.plain)` full-width rows (`contentShape(.rect)`), no chevron; a click opens the sheet.
- **Action buttons inside a section** (New Routine, Add Login…, Add Shop…, Add Card… / Replace Card…, Update Shops, Connect…, Disconnect…, Try Again): system button rows on iOS (accent text, Disconnect red), leading push buttons on the Mac, as System Settings.
- **Destructive section** (Delete Bot, Disband Group): on iOS a red button row; on the Mac a destructive push button at the leading edge of its own section.
- **Swipe actions** (iOS only; a Mac grouped Form gets none): a red-tinted trash button without the destructive role and with `allowsFullSwipe: false`, so the row never animates away before the confirmation or the server answers, and its spinner and failure line stay visible. The Mac uses the context menu (and the routine ellipsis menu).
- **Offline:** context-menu and swipe items stay visible and disabled, as today, so the action stays discoverable.
- **Accessibility:** today's named actions stay on both platforms (Edit Login, Remove Login, Remove Shop); task rows keep their combined element with the status value.
- **Field labels:** Name, Role, Description and the group name use `.labelsHidden()`, so the Mac Form draws no label column; the `TextEditor`s have none.
- **Section headers** keep title case ("Other Conversations", "Current Run").

## Header (all tabs)

- One section with a clear row background and no separators: the 96 pt avatar, the name (`.title2.bold()`, centred), the role (secondary, centred, prompt "Add Role"), the save status line (Saving…, Saved, the failure with Try Again, otherwise the profile name), and the Routine action circle (hit target at least 44 pt). Once loaded these are the same views and rules as today (`docs/flows/bot-roles.md`), including the name and role focus fill. The Look editor stays a popover anchored on the avatar (a sheet on iPhone).
- **Loading (draft not loaded yet), a change from today:** identity shows at full contrast. The avatar is a plain image (the cached roster photo, as today), the name and role are plain `Text` in the same fonts (the role line is omitted when empty, never a dimmed "Add Role"). Nothing in the header is dimmed with `.disabled`. VoiceOver reads the name text and the avatar is decorative (no "Edit Look" until it can be used). Once loaded, the avatar becomes the Edit Look button and the name and role become the editable fields, in place, with the same fonts and padding. The Routine action circle works without the profile, so it stays enabled as today.
- **Failed load:** as today, Description, Instructions and Soul show spinners and Rich UI and Capabilities stay disabled; identity keeps showing as text. (Retrying a failed profile load is not part of this change; PLAN keeps it as an open item.)

## Tab picker

- `Picker(selection: $tab)` with `.pickerStyle(.segmented)` and `.labelsHidden()`, segments Info, Tasks, Routines, Passwords, in its own clear-background row under the header, full row width. Replaces the custom text tabs with the glass capsule, their `ViewThatFits` fallbacks and horizontal scroll.
- The Routine action circle still selects Routines and opens New Routine.
- **Narrow:** the Mac's 280 pt minimum (`inspector-passwords-narrow`) is a gate: "Passwords" must not truncate. If it does with the default Form insets, the picker row gets smaller horizontal insets, then the Mac's `.controlSize(.small)` (Mac inspectors use small controls). On iPhone at accessibility text sizes the segmented control caps its text size and offers the Large Content Viewer on long press, as UIKit does for every segmented control; accepted, no custom fallback.
- VoiceOver reads it as a segmented control with the selected segment, replacing the hand-set `.isSelected` traits.

## Info tab

Sections in today's order, each with its title as the section header and today's footer text as the section footer:

1. **(no header)** `LabeledContent` rows: Model, Profile, Server (when known), Messages, Last Active (when the bot has a canonical session), replacing the hand-built `Grid` card. Values wrap, as today. Model is a `Menu` with the model list (`ModelPicker`, inline) whose label is the current model and `chevron.up.chevron.down`, the look of a system menu picker value, with the spinner beside it while changing; disabled offline or while changing, as today. Without providers it shows the model as text. The "Last Active" label stays (the iOS UI test uses it).
2. **Description:** a vertical `TextField` (prompt "What this bot is for"). While loading: a small spinner row, as today.
3. **Instructions** (footer as today): a multi-line `TextEditor` with the placeholder, so Return inserts a new line on the Mac (a vertical `TextField` would submit there). It grows with its text; the Form scrolls. While loading: a spinner row.
4. **Rich UI** (footer as today): the "Cards and Forms" switch. Disabled until loaded.
5. **Soul** (footer as today): as Instructions.
6. **Capabilities:** Skills, Toolsets, MCP Servers rows, each with its icon, title and "enabled/total" as the trailing value, opening the toggle list sheet with Done, as today. Disabled until loaded.
7. **Other Conversations** (footer as today): one row per session (title, then "source · relative time" in caption secondary) that opens the read-only transcript sheet, as today. Empty: "No other conversations" (secondary). Error: the error with the warning symbol. Loading: spinner row.
8. **Delete Bot** (not for the default bot): its own section, `Button("Delete Bot", role: .destructive)`. It opens the same confirmation (`BotDeletion`). Disabled offline.

## Tasks tab

- **Has todos:** one section, header "Current Run" or "Last Run" with "n of m done" on the trailing side, one row per todo with today's status symbol, tint, strike-through and pulse. System separators replace the manual dividers.
- **Empty:** `ContentUnavailableView` "No Tasks" with today's text, in a clear-background row.

## Routines tab

- **Loaded with jobs:** one section of routine rows (title, Paused badge, schedule, next run, last result, issue as today). Each row has:
  - swipe actions on iOS (trailing: Delete, which asks first; leading: Pause/Resume);
  - a context menu (long press, right click) with Run Now, Pause/Resume and Delete…;
  - a trailing borderless `Menu` with the ellipsis and the same actions, hit area 44 pt on iOS, so the actions stay discoverable; while a request runs it is replaced by a small spinner, as today.
  The 28 pt glass circle goes. Delete asks with today's confirmation dialog; failures show today's alert.
- A **New Routine** button row (plus symbol) in its own section under the list.
- **Empty:** `ContentUnavailableView` "No Routines" with the New Routine button (`.bordered`, no glass), in a clear-background row. **Loading:** spinner row. **Couldn't load:** `ContentUnavailableView` "Couldn't Load Routines" with the error.
- Offline: Run Now, Pause and Delete fail with today's alert (no change).

## Passwords tab

Each of today's three cards becomes one section: header as the card title, the footers that apply (today's text and conditions) as the section footer, one paragraph each.

- **Logins:** rows sorted as today. An editable Hermes vault login is a button row (tap opens Edit Login), with the swipe action (Remove, opens today's "Remove the login for …?" confirmation; never removes without asking) and the context menu (Edit Login…, Remove Login…). A codes row offers Remove only. 1Password rows are plain rows with no actions. Removing shows a spinner in the row, a failure the red line, a new or edited row highlights briefly (the Shops tint), all as today. Below the rows, an **Add Login…** button row. Couldn't load: "Couldn't load logins." (or the 1Password-token variant) with Try Again, above the last rows. Empty: "Ada has no saved logins." Loading: spinner row.
- **1Password:** a status row (symbol and title) and, when the state has one, the action (Connect…, Try Again, Disconnect… in red); the failure line in red; footnotes as the footer. Disconnect asks first, as today.
- **Shops** (when crew-push lists payments): the card row (caption, card art, label and last four, "Kept here, never used to pay." on the default bot with old crew-push, the code-mismatch warning, Replace Card…; or "No card on the server" / "More than one card on the server" with its text and Add Card…), one row per shop with the swipe action (Remove Shop) and the context menu, or "Ada can't pay anywhere yet." when there are none, the Update Shops row with its stale text and failure, and **Add Shop…**. Footers as today, "Payments are off" in red. Remove keeps today's behaviour (immediate, no confirmation, a spinner, then the row leaves or shows the red failure line), since a shop can be added back at once and today's context menu does the same.
- Couldn't load shops: the line with Try Again. Loading: spinner row.
- **Disabled rules and conditional rows, unchanged:** Add Login (offline or the list failed), Add Shop (`canAddShop`), Add/Replace Card (`canEditCard`), Update Shops (`canUpdateShops`) and its visibility (`showsUpdateShops`), every Try Again, Connect… and Disconnect… (offline), the swipe and menu actions (offline). Add Login shows only once a list has loaded; footers only once items exist.

## Group inspector

- Same shell: one grouped `Form`, the clear header section (group avatar, editable name, rename status; the name field disabled offline or while renaming, as today), a **Members** section of button rows (avatar, name, role) that open that bot's chat (the tap switches the selection, so no chevron, as a Messages contact row in details), disabled and dimmed for a member whose bot is gone, and a **Disband Group** destructive section (disabled offline) with today's confirmation and alert. The hand-drawn chevrons go.

## Avatar picker (Look popover and New Bot sheet)

- Shape tiles: 44 pt avatars in a 64 pt minimum-height tile; the selected shape gets a 2 pt accent ring around the tile (no glass, no tinted glass in content).
- Colour swatches: 44 pt hit targets (the circle with its 4 pt inset ring), grid minimum 44; the selected colour keeps its 2 pt primary ring.
- Expression rows, Choose Photo, Remove Photo and Reset unchanged.

## Surfaces

- **iPhone:** the pushed bot page from the persona pill; all sheets as today.
- **iPad:** the same pushed page in the detail column (iOS pushes the inspector from `ChatScreen` on every size class); the segmented control and sections adapt to the wider column.
- **Mac main window:** the `.inspector` column for a bot and for a group. **Mac chat window:** the same `BotInspector` in its inspector.
- **Light and dark:** system grouped backgrounds, row backgrounds and separators; checked in renders.
- **Other surfaces:** bot list rows, previews, unread, push, the chat, the composer, the persona pill and the New Bot sheet's layout do not change. The New Bot sheet shows the avatar picker change only.

## States

- Loading, editable, saving, saved, save failure with Try Again, failed load, offline (controls that need the server disabled, last data kept), and empty and error per tab as listed above.
- **Long content:** long names wrap in the header; long Soul and Instructions grow their rows; long hosts and usernames truncate in the middle on one line; long model names and server hosts wrap in their `LabeledContent` value; many logins, routines or conversations grow their sections and the Form scrolls.
- **Default bot:** no Delete Bot section; the 1Password and Shops default-bot rules as today.

## Removed

`Card`, the tab row (`tabs`, `tabRow`, `ViewThatFits`, horizontal `ScrollView`), `BotInfo`'s `Grid` card, the custom Delete Bot and Disband Group rectangles, the self-drawn `chevron.forward` rows (Capabilities, Other Conversations, group members), `onTapGesture` login rows, the routine row's glass circle, the routines' and tasks' fill containers, the avatar picker's glass selection, the routines empty state's glass button.

## Docs

- `docs/PLAN.md`: the Decisions "Bot inspector" line and the Navigation macOS and iOS lines describe the segmented control and grouped Form instead of text tabs with a glass capsule and cards (and Passwords instead of the stale "Files"); a Decisions line records this rebuild. No locked UI value changes: the inspector width and close button lines stay as written.
- `docs/flows/inspector-passwords.md`: its Tab row section, the "grow the card" long-content line and the tab-row renders line point to this spec.
- `docs/flows/bot-roles.md`: "Disabled until the draft has loaded" becomes "shown as text until the draft has loaded".

## Tests

- A container and control rebuild with behaviour kept, so the proof is renders plus a reviewer using it, and the existing unit tests (`PasswordsTests`, `ProfileDraftTests`, payments tests) staying green, since their logic is untouched.
- UI test (iOS Simulator, fixtures, runs on `main`): on the `inspector-passwords` fixture the segmented control switches to Info and back to Passwords; swiping a login row and tapping Remove asks, and confirming records one `vault.remove` in the request log. Shown failing before (no segmented control, no swipe action).
- `ChatInspectorUITests` keeps passing (it opens the inspector and waits for "Last Active").
- Renders, before and after, light and dark, Mac via `./snapshot.sh` and iOS on a private simulator deleted afterwards: `inspector-info` (top and scrolled to the bottom with Delete Bot), `inspector-tasks`, `inspector-routines`, `inspector-look`, `inspector-passwords`, `inspector-passwords-empty`, `inspector-passwords-error`, `inspector-passwords-offline`, `inspector-passwords-narrow` (Mac 280 pt, iPhone accessibility text), `inspector-shops`, `inspector-shops-no-card`, `bot-page` (loading header at full contrast), `layout-inspector`, `chat-window-inspector`, `group-inspector`, `avatar-picker`, `new-bot`, `profile-skills`, plus an iPad render of the bot page. Key after renders saved as `docs/flows/renders/inspector-rebuild-*.png`.
- Real server: the Hermes calls are unchanged, so no new probe; the fixtures stand in for the views.
