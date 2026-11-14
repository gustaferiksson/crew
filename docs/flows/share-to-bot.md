# Share sheet: send a link, text, photo or file to a bot (#360)

Getting a web page, a photo or a PDF to a bot today means copying it into the chat by hand. New: a Share extension, "Crew" in the system share sheet, with a compose sheet that picks a bot and takes an optional note, then sends the item into that bot's Bot Chat through the same attachment path the composer uses. Model: Notes' and Reminders' share extensions (a note, the item's preview, a destination row, Cancel and a confirm button) and Messages (Send, straight from the sheet).

## Decision: the extension sends itself

Apple's own share extensions (Messages, Mail, Notes) finish the job inside the sheet; a handoff through the App Group would leave the item unsent until the user next opens Crew, and the share sheet can't open the containing app. Crew already sends from outside the app with tested code: Ask Bot and Talk to Bot connect a short-lived gateway from the Keychain session (`restoredURLSession`, `connectedGateway`), open the Bot Chat (`openBotChat`) and `prompt.submit`. The extension does the same, plus the composer's attach step (`image.attach_bytes`, `file.attach`), pulled out of `ChatSession.submit` into one function both call.

- **Credentials:** the extension reads the existing Keychain item (`session`, service `dev.gustaf.crew`) through a `keychain-access-groups` entitlement that names the app's own group (`$(AppIdentifierPrefix)dev.gustaf.crew`, where the app's items already live), read-only. Nothing is moved, re-saved or stored anywhere new; the app's entitlements don't change. Refreshed cookies are not written back (same as Ask Bot).
- **Bots:** `voice-bots.json` in the App Group (already written by the app for Siri and the widget), so the picker works without a network round trip.
- **The sheet stays up while sending.** HIG prefers dismissing at once and finishing in the background, but the only way to run a task after dismissal is a background `URLSession` upload, and Hermes takes attachments and prompts as gateway WebSocket RPCs. So the sheet shows progress until `prompt.submit` is accepted (an extension isn't suspended while visible), with the gateway's 15 s connect limit, then one 30 s deadline over open, attach and submit; the gateway then disconnects (as Talk to Bot does).
- **Why a SwiftUI `Form`, not `SLComposeServiceViewController`:** the system compose view's configuration rows are UIKit table items with no avatar or SwiftUI hosting; the `Form` keeps its layout (a pushed "To" list, note, preview) with system components only.

## Surfaces

- **Share sheet, iPhone and iPad:** "Crew" in the apps row for links, text, images, PDFs and other files (activation rule below). Tapping it shows the compose sheet: a `NavigationStack` with Cancel (leading), title "Crew", Send (trailing, confirmation action). A `Form`:
  - **To row:** a `Picker` with `.navigationLink` style ("To", value = the bot's avatar and title). Listed bots sorted most recently active first (`lastActive`), hidden bots left out. Default: the most recently active bot (`VoiceBot.choose`). First, as Messages' share sheet puts "To" first, so the focused note's keyboard never hides who receives it.
  - **Note:** a multi-line `TextField` "Add a note" (`axis: .vertical`, 1 to 6 lines, then it scrolls), focused when the sheet opens, as in Notes' share sheet.
  - **Preview section:** one row per item: a link shows a `link` symbol, the page title when the share carries one (Safari's `attributedContentText`), else the host, and the URL (secondary, one line, truncated in the middle); text shows its first 4 lines; an image shows its thumbnail (60 pt, rounded) and file name; a file shows the document symbol, its name (middle truncation) and size. Several items list in share order. Rich link cards (`LPLinkView`) and file thumbnails (`QLThumbnailGenerator`) are a follow-up.
  - iPad shows it as the system's form sheet; nothing custom.
- **Mac:** not in this slice. The Mac app has no App Group and every new bundle id needs its own Developer ID profile; a macOS share extension is a follow-up.
- **Crew, that bot's chat (iPhone and Mac):** the share is an ordinary user turn in the Bot Chat: the note and link(s) as the bubble's text, images and files as its attachments (the composer's rendering: `@file:` refs parsed back by `Prompt(raw:)`), then the bot's reply as usual. A chat that is open in Crew at the time shows it through its usual live sync.
- **Bot list:** preview, time and unread change as for a typed message, through the usual sync; nothing new.
- **Push:** the bot's reply sends crew-push's usual notification; the share adds none.
- **Siri share suggestions (`INSendMessageIntent` donations, bots in the share sheet's top row):** follow-up; they need donations from every send in the app and the extension to handle `extensionContext.intent`.
- **Light/dark:** system `Form` colours only.

## Item types

Per `NSItemProvider`, the first match wins, so one Safari item that carries both a URL and the page's text sends the URL only:

1. **Image, PDF or other file** (a registered type that conforms to `public.data` but is not text or a URL): its file representation goes through `Attachment(contentsOf:)`: images become image attachments (HEIC/large ones re-encoded and downscaled to 2048 px, as the composer does), everything else a file attachment.
2. **URL:** a file URL is read as a file (above); a web URL becomes a line of text.
3. **Plain text:** a block of text.

The message is the note, then each link or text, separated by blank lines. Images only and no text sends the composer's image-only prompt. Activation rule: up to 8 images or files (`Attachment.maxCount`), up to 8 web links, text. Long text (a whole selected article) is sent whole, as the composer does. Movies are not offered (no video in the composer either).

## States

- **Loading the items:** the preview rows show a `ProgressView`; Send is disabled until all are read.
- **Too large or too many:** the rooms' smaller limits (`Attachment.Limits.room`: 15 MB per file, 25 MB per message, 8 files), because the whole message sits in the extension's memory, and the composer's error texts ("Report.pdf is larger than 15 MB.") as the preview section's footer, in red; Send disabled. The user can still Cancel.
- **Unreadable item or a folder:** the composer's error text ("Crew couldn't read …", "… is a folder."), Send disabled.
- **Nothing sendable** (empty text): Send disabled.
- **Not signed in** (no Keychain session): a `ContentUnavailableView` "Sign in to Crew" with "Open Crew and sign in, then share again.", only Cancel.
- **No bots cached** (Crew never opened since install, or no listed bots): `ContentUnavailableView` "No Bots" with "Open Crew to load your bots.", only Cancel.
- **Sending:** Send becomes a `ProgressView`, the form is disabled; Cancel stays and closes the sheet at once, disconnecting the gateway. Before `prompt.submit` went out nothing is delivered (staged images are left to the session's next prompt, as after a dropped connection in the app); once it went out the message may still arrive, which is the usual meaning of cancelling a send in flight.
- **Sent:** the sheet closes (`completeRequest`) as soon as `prompt.submit` is accepted. No extra confirmation.
- **Offline, server unreachable, send failure, deadline:** the error text (`HermesError`'s, e.g. "Can't reach … Check your connection or VPN."; a dropped or timed-out gateway says "Couldn't send. Check your connection and try again.") inline as a red footer under the note (no alert: HIG keeps modal views off extensions), the sheet keeps everything as typed and Send is enabled again for a retry. Images staged before the failure are detached (the composer's rule). Nothing is saved to the bot's draft: drafts are app-process state, and the content stays in the open sheet.
- **Session expired (401):** the inline error says "Your session expired. Sign in again." (`HermesError.unauthorized`); the extension never shows a login form.
- **Bot busy with another turn** (`openBotChat` snapshot `running`): text-only shares submit and the server queues them (`prompt.submit` → `queued`, as Ask Bot relies on). Shares with attachments are refused with "<Bot> is busy. Try again when it's done." (inline, Send re-enabled): staged attachments wait for the *next* `prompt.submit`, and the composer never stages during a running turn either. Waiting for the turn to finish is a follow-up.
- **Bot deleted since the cache was written:** `openBotChat` fails → the send failure alert.
- **Long content:** a long note scrolls inside its field after 6 lines; long text previews clamp to 4 lines; long names truncate in the middle; many items scroll in the form.
- **Memory:** the extension's memory budget is far smaller than the app's. Each item is read once into its attachment (large images re-encoded to at most 2048 px on read, as the composer does), and staging base64-encodes one attachment at a time, so the peak is the message (at most 25 MB) plus one encoded file and its frame. Peak memory on a device is not measured yet (see Verification).

## Verification

- Unit (CrewTests, macOS): item type choice (image, PDF, a Safari URL+text item, file URL, plain text), message composition (note + links + text, image-only), limits (too large, too many) through `Attachment.validated`, and the attach requests (`image.attach_bytes` / `file.attach` params) the shared send function builds. Each shown failing without the change.
- Real server: `Tests/chat_probe/run.sh share` runs the extension's send function on `crew-test` with a note, a link, a PNG and a PDF, then reads the Bot Chat history back and checks the user row carries the note, the link and both attachments.
- Build: `./build.sh` (both platforms) with zero warnings; the iOS app embeds `CrewShare.appex`.
- Render: `./snapshot.sh ios share-sheet share-sheet-too-large` hosts the compose view with fixture items (light/dark) on a private simulator.
- Not verifiable headless or unsigned: the real share sheet, the Keychain read through the access group (unsigned simulator builds carry no entitlements), and peak memory on a device for the 25 MB worst case; checked through a signed release once the profile exists.

## Release

`dev.gustaf.crew.share` is a new bundle id, and Ad Hoc signing is manual per bundle id. Until its App ID and `Crew Share Ad Hoc` profile exist, the Release configuration leaves `CrewShare.appex` out of `Crew.app` (`EXCLUDED_SOURCE_FILE_NAMES` on the app, signing off on the appex), so tagged releases keep building and ship without the extension. Wiring it in then mirrors the widget's: Release signing in `project.yml`, `ExportOptions-AdHoc.plist`, `package.sh`, `release.yml`'s preflight and the `IOS_SHARE_ADHOC_PROFILE` secret.
