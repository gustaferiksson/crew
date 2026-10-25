# Action button voice (#185)

Press the iPhone Action button (or the Control in Control Center or on the Lock Screen, or the "Talk to Bot" shortcut), speak, and the message goes to a bot's Bot Chat without opening Crew. The reply arrives as the usual crew-push notification. Model: Voice Memos' Lock Screen recording plus Messages' send.

## Pieces (Apple's documented APIs only)

- `TalkToBotIntent`: `AudioRecordingIntent` and `LiveActivityIntent`, so it runs in the app's process (the Live Activity can only start there). Bot parameter is an `AppEntity` read from the App Group cache; no choice means the most recent listed bot.
- `TalkControl`: a `ControlWidget` (`AppIntentControlConfiguration`, configurable bot) in the `CrewWidgets` extension. It shows in Settings > Action Button > Controls, Control Center and the Lock Screen.
- Live Activity (`VoiceAttributes`, same extension): Lock Screen banner, expanded, compact and minimal Dynamic Island. Cancel and Send are `LiveActivityIntent` buttons. Pressing the Action button again while recording also sends.
- Recording and transcription reuse `Dictation` (on-device `SpeechAnalyzer`, else Hermes `api/audio/transcribe`). The send reuses `openBotChat` (Bot Chat resolve/create, as the chat screen does) and `prompt.submit` on a short-lived gateway built from the Keychain session, like the Deny push action. The gateway disconnects right after the submit. Hermes detaches the session and the turn finishes and pushes (probed on `crew-test`: `Tests/chat_probe/run.sh voice`).
- App Group `group.dev.gustaf.crew` (iOS only): `voice-bots.json` (name, title, look, Bot Chat id, last active, hidden), written whenever the roster is saved, and the avatar photo cache, so the Control's picker and the Live Activity avatar work without the app.

## Surfaces

- **Action button / Control:** the Control's label is the chosen bot's title or "Talk to Bot", with the `waveform` glyph.
- **Live Activity, recording:** avatar (photo or shape), bot title, elapsed time (`Text(timerInterval:)`, no per-second updates), pulsing red waveform; Cancel (bordered) and Send (prominent).
- **Sending:** "Sending…", no buttons. **Sent:** "Sent to <bot>" with a green check, then it ends after 4 s.
- **Compact island:** avatar leading, phase glyph trailing. **Minimal:** avatar.
- **Bot list and chat:** unchanged. The prompt and reply appear in the Bot Chat like any other turn (time, preview, unread and Working come from the server as usual). The reply notification is the normal crew-push one.
- **Mac:** no Action button, so no Control or Live Activity there. The macOS build is unchanged.
- **Light/dark:** system materials and colours; see the `voice-activity` renders.

## States

- Signed out: the intent asks to continue in Crew ("Sign in to Crew first.").
- No bots cached yet: continue in Crew ("Open Crew to load your bots.").
- Microphone permission not asked yet: continue in the foreground, where `Dictation` asks, then recording starts. Denied: the intent fails with `Dictation`'s "Allow Crew to use the microphone in Settings" message.
- Nothing heard: "Crew didn't hear anything.", ends after 4 s.
- Transcription failed: the error shows in the Live Activity, which stays until dismissed.
- Offline or the server unreachable: "Couldn't send. It's saved as a draft." The text is added to that bot's composer draft, so opening the chat shows it ready to send.
- Cancelled: the recording is discarded and the Live Activity ends at once.
- Long dictation: no cap. The elapsed time keeps counting. Server transcription of long audio is bounded by its 60 s timeout and then shows the failure state.
- Hidden bot chosen on the Control: still used (it was an explicit choice); the default skips hidden bots.

## Verification

- Unit: `VoiceBotTests` (bot choice: explicit, hidden, deleted, empty).
- Real server: `Tests/chat_probe/run.sh voice` submits on `crew-test`, disconnects at once, and finds the reply in history.
- Renders: `./snapshot.sh ios voice-activity` hosts the Live Activity's content views and a stand-in compact island in the app. The real Dynamic Island chrome, the Control in Control Center and the Action button can't be rendered or driven off-device.
- Release signing: `./package.sh ios` archives and exports with `Crew Ad Hoc` and `Crew Widgets Ad Hoc`; both bundles carry the App Group.
- Not verified: the Action button and background recording on a device (never installed on the user's devices). Ships for checking through a tagged release.
