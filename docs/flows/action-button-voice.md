# Action button voice message (#185)

Press the iPhone Action button (or the Control in Control Center or on the Lock Screen, or the "Talk to Bot" shortcut), speak, press again, and the message goes to a bot's Bot Chat without opening Crew. The reply arrives as the usual crew-push notification. Model: Voice Memos' Lock Screen recording plus Messages' send. A spoken call (PR #207) was tried and replaced on the user's request: they want to record a message and have it sent when they're done.

## Pieces (Apple's documented APIs only)

- `TalkToBotIntent`: `AudioRecordingIntent` and `LiveActivityIntent`. Apple documents that an intent conforming to `LiveActivityIntent` is performed in the app's process (on the user's phone it runs in `IntentMode.background`), so the copy compiled into the widget extension has a stub `perform()` and the app's copy does the work. The intent toggles: nothing recording starts a recording, a recording in progress is sent.
- `TalkControl`: a `ControlWidget` (`AppIntentControlConfiguration`, configurable bot) in the `CrewWidgets` extension. It shows in Settings > Action Button > Controls, Control Center and the Lock Screen, with the `waveform` glyph.
- `VoiceMessage` (app): starts the Live Activity, then `Dictation` with `.playAndRecord`, Bluetooth HFP and `.duckOthers`, so the app keeps recording in the background. The session must be mixable: a background app activating a non-mixable session gets "Operation denied. Cannot interrupt others" (-12985, seen on the user's phone from the Action button). Transcription is the on-device `SpeechAnalyzer`, else Hermes `api/audio/transcribe` after the recording stops.
- Send: `openBotChat` (Bot Chat resolve/create, as the chat screen does) and `prompt.submit` on a short-lived gateway built from the Keychain session, which disconnects right after the submit. Hermes detaches the session and the turn finishes and pushes (probed on `crew-test`: `Tests/chat_probe/run.sh voice`).
- Cancel and Send in the Live Activity are `LiveActivityIntent` buttons.
- App Group `group.dev.gustaf.crew` (iOS only): `voice-bots.json` and the avatar cache, so the Control's picker and the Live Activity avatar work without the app.

## Surfaces

- **Action button / Control:** label is the chosen bot's title or "Talk to Bot". First press: recording starts. Second press: it is sent.
- **Expanded island** (modeled on Phone's call and Voice Memos): the leading region holds the bot's avatar (44 pt) and the trailing region the red animated `waveform` glyph with the elapsed time in red, so both sit beside the TrueDepth camera at the same height and expand from the compact avatar and timer. The bottom region is one row: bot name, then round Cancel (xmark, gray) and Send (arrow, accent) at 44 pt, all centered on the same line. No center region: it sits below the camera, which is what made the name and time look misplaced in v0.1.39. While sending, sent or failed, the trailing glyph becomes the phase icon and the row shows the status under the name (failures in red, with Cancel).
- **Lock Screen banner:** avatar, name over the red waveform glyph and the elapsed time (`Text(timerInterval:)`, no per-second updates), round Cancel and Send trailing, 14 pt margins. **Sending:** "Sending…", no buttons. **Sent:** green check and "Sent" for 3 s, then the Live Activity ends.
- **Compact island:** avatar leading; elapsed time in red while recording, then an arrow (sending), a green check (sent) or a red exclamation mark (failed). **Minimal:** the red animated waveform while recording (live state, not a logo), else the same phase icon.
- **Tap:** every presentation carries `widgetURL(crew://chat/<profile>)`, so tapping the island or the banner opens Crew straight to that bot's chat (`onOpenURL` feeds the same route a notification tap uses).
- **In Crew, that bot's chat:** the composer becomes the recording row, like in-composer dictation: Cancel in the attach button's place, the live level meter, the red waveform and the elapsed time in the field, Send as the field's action button. Sending shows a spinner and "Sending…"; Sent a green check for 3 s, then the normal composer returns; a failure shows the message in red with Cancel. Cancel and Send call the same `VoiceMessage` as the Live Activity's buttons, so either place updates or ends the other.
- **In Crew, elsewhere (bot list, other bots' chats, group chats):** a glass capsule in the bottom bar (above the search field in the list, above the composer in a chat): avatar, name over the waveform and time, Cancel and Send. Tapping the avatar or name opens the recording bot's chat. Crew has no `TabView`, so this is a `safeAreaBar` item rather than `tabViewBottomAccessory`; the list's bottom edge effect switches to `.hard` while it shows so rows don't read through it.
- **Bot list and chat:** the message is a normal prompt in the bot's Bot Chat, so preview, time, unread and Working behave as for typed messages. The reply notification is the normal crew-push one.
- **Mac:** no Action button, so no Control or Live Activity there. The macOS build is unchanged.
- **Light/dark:** system materials and colours; see the `voice-activity` renders.

## States

- Signed out: Crew opens ("Sign in to Crew first.").
- No bots cached yet: Crew opens ("Open Crew to load your bots.").
- Microphone permission not asked yet: Crew comes to the foreground without a confirmation (`continueInForeground(_:alwaysConfirm: false)`; the press runs in a sceneless runner that can't show one), asks for the microphone, then recording starts. Denied: the Live Activity shows `Dictation`'s "Allow Crew to use the microphone in Settings" message.
- Crew can't come to the foreground: the Live Activity shows the reason with Cancel (when a bot is cached), and the intent's error goes to the system.
- Nothing heard: "Crew didn't hear anything." for 3 s, then it ends.
- Transcription failed: the error stays in the Live Activity with Cancel.
- Offline or the server unreachable: "Couldn't send. It's saved as a draft." stays with Cancel. The text is added to that bot's composer draft, so opening the chat shows it ready to send.
- Every failure keeps the Live Activity in the island and on the Lock Screen until Cancel or the next press, instead of vanishing (ending a Live Activity removes it from the island at once, which hid every v0.1.35 failure).
- Cancelled (from the island, the banner, the composer or the capsule): the recording is discarded, the Live Activity ends at once and the in-app row or capsule disappears.
- Sent from either side: the Live Activity and the in-app row both show Sent for 3 s, then both end.
- Press while sending: ignored until the transcript is ready; a press after that starts a new recording.
- Long recording: no cap. Server transcription of long audio is bounded by its 60 s timeout and then shows the failure state.
- Hidden bot chosen on the Control: still used (it was an explicit choice); the default skips hidden bots.

## Not possible: hold to talk

Holding the Action button to talk and releasing to send would need the button's release. A control's intent runs once per press ("When someone interacts with a control, it performs its action using an app intent", WidgetKit, Creating controls to perform actions across the system), and no public API reports the Action button's release or hold time to a third-party app. `AVCaptureEventInteraction` reports press phases but "you can only use this API for capture use cases. The system sends capture events only to apps that actively use the camera" (AVKit). Push to Talk's transmit sources are the system UI button, the app, and a hands-free device's button (`PTChannelTransmitRequestSource`), not the Action button. So the button is tap to start and tap again to send.

## Verification

- Unit: `VoiceBotTests` (bot choice: explicit, hidden, deleted, empty).
- Real server: `Tests/chat_probe/run.sh voice` submits on `crew-test`, disconnects at once, and finds the reply in history.
- Unit: `theLiveActivityLinkOpensThatBotsChat` (the deep link parses to that bot's route; other URLs don't).
- Renders: `./snapshot.sh ios voice-activity` hosts the Lock Screen row for every phase plus stand-ins for the expanded (top band beside a camera-sized capsule, bottom row), compact and minimal island; `chat-voice` shows the recording composer and `sidebar-voice` the capsule on the bot list, light and dark. The real island chrome, the Control and the Action button can't be rendered or driven off-device.
- Simulator: a press of the Control or of the Action button runs `TalkToBotIntent` in Crew only in a signed build (ad hoc `CODE_SIGN_IDENTITY=-`); unsigned, siriactionsd rejects the extension (`missingLNAction`).
- Each step logs to subsystem `dev.gustaf.crew`, category `voice` (notice level, so a sysdiagnose keeps it): perform and its mode, toggle, early returns, Live Activity request, audio start (on device or server), transcription, gateway, submit, dismiss.
- Not verified off-device: background recording from the Action button end to end and Bluetooth routing. Ships for checking through a tagged release.
