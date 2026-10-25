# Action button voice call (#185)

Press the iPhone Action button (or the Control in Control Center or on the Lock Screen, or the "Talk to Bot" shortcut) and you are on a call with a bot: you talk, it answers out loud, you talk again, until you press the button again or tap the red End button in the Dynamic Island. Model: a phone call's Live Activity (avatar, name, running time, red End) with Grok's Action button voice mode as the reference.

## Pieces (Apple's documented APIs only)

- `TalkToBotIntent`: `AudioRecordingIntent` and `LiveActivityIntent`. Apple documents that an intent conforming to `LiveActivityIntent` is performed in the app's process, so the copy compiled into the widget extension has a stub `perform()` and the app's copy does the work. The intent toggles: no call starts one, a call in progress ends.
- `TalkControl`: a `ControlWidget` (`AppIntentControlConfiguration`, configurable bot) in the `CrewWidgets` extension. It shows in Settings > Action Button > Controls, Control Center and the Lock Screen, with the `phone.fill` glyph.
- `VoiceCall` (app): starts the Live Activity, then one `Dictation` for the whole call with `.playAndRecord`, `.defaultToSpeaker` and Bluetooth HFP, so the app keeps running in the background. Calls need the on-device `SpeechAnalyzer`; the server transcription fallback can't hear turn ends.
- Turn taking (`VoiceTurn`, unit tested): once the input level has stayed under about -32 dB for about 1 s after new words, the turn ends. If the transcriber still holds volatile words then, Crew asks it to finalize them (`SpeechAnalyzer.finalize(through:)`) and sends once they settle. The new words are sent with `prompt.submit` on one gateway connected for the whole call (Bot Chat via `openBotChat`). The reply is the `message.complete` text for that session.
- Speaking: Hermes `POST api/audio/speak` (MP3 from the server's TTS provider, probed on `crew-test`), played through an `AVAudioPlayerNode`; if that fails, `AVSpeechSynthesizer` with the best installed system voice for the language. Markdown is stripped first. Input is paused while the bot thinks and speaks (half duplex), so the bot never hears itself.
- App Group `group.dev.gustaf.crew` (iOS only): `voice-bots.json` and the avatar cache, so the Control's picker and the Live Activity avatar work without the app.

## Surfaces

- **Action button / Control:** label is the chosen bot's title or "Talk to Bot". First press: call starts. Second press: call ends.
- **Expanded island:** avatar leading; bot name over "0:12 · Listening" (elapsed time from `Text(timerInterval:)`, then the phase); red round End button trailing. No mute.
- **Compact island:** avatar leading, running time trailing in green like a call. On failure the trailing side is a red exclamation mark. **Minimal:** avatar.
- **Lock Screen banner:** the same row as the expanded island.
- **Phases:** Connecting… (gateway and speech model starting), Listening, Thinking… (turn sent, waiting for the reply), Speaking, then Listening again.
- **Bot list and chat:** each turn is a normal prompt and reply in the bot's Bot Chat, so preview, time, unread and Working behave as for typed messages. crew-push may also notify the reply, as for any turn.
- **Mac:** no Action button, so no Control or Live Activity there. The macOS build is unchanged.
- **Light/dark:** system materials and colours; see the `voice-activity` renders.

## States

- Signed out: the intent asks to continue in Crew ("Sign in to Crew first.").
- No bots cached yet: continue in Crew ("Open Crew to load your bots.").
- Microphone permission not asked yet: continue in the foreground, where `Dictation` asks, then the call starts. Denied: the island shows `Dictation`'s "Allow Crew to use the microphone in Settings" message.
- No on-device speech model for the language: "Calls need on-device speech recognition for your language."
- Offline or server unreachable at the start: "Couldn't reach the server."
- A turn that can't be sent: "Couldn't send. It's saved as a draft." The words are added to that bot's composer draft.
- The bot's turn fails or is interrupted: its error shows in the island.
- Every failure keeps the Live Activity in the island with the message and the End button until ended, instead of vanishing.
- Silence: the call keeps listening; nothing is sent until there are words.
- Long replies: spoken in full; End stops the voice at once.
- Ended (End or second press): audio stops, the gateway disconnects, the Live Activity ends immediately. A turn already sent still finishes on the server and lands in the Bot Chat.
- Hidden bot chosen on the Control: still used (it was an explicit choice); the default skips hidden bots.

## Not possible: hold to talk

Holding the Action button to talk and releasing to send would need the button's release. A control's intent runs once per press ("When someone interacts with a control, it performs its action using an app intent", WidgetKit, Creating controls to perform actions across the system), and no public API reports the Action button's release or hold time to a third-party app. `AVCaptureEventInteraction` reports press phases but "you can only use this API for capture use cases. The system sends capture events only to apps that actively use the camera" (AVKit). Push to Talk's transmit sources are the system UI button, the app, and a hands-free device's button (`PTChannelTransmitRequestSource`), not the Action button, and it is a walkie-talkie channel service with its own entitlement. So the button is tap to start and tap again to end.

## Verification

- Unit: `VoiceBotTests` (bot choice), `VoiceTurnTests` (turn end: settled text, quiet span, only new words).
- Real server: `Tests/chat_probe/run.sh voice` runs two turns on `crew-test` over one connected gateway, checks each `message.complete` reply, and fetches the spoken MP3 from `api/audio/speak`.
- Renders: `./snapshot.sh ios voice-activity` hosts the Lock Screen row for every phase plus stand-ins for the expanded and compact island. The real island chrome, the Control and the Action button can't be rendered or driven off-device.
- Not verified off-device: starting from the Action button in the background, background audio across turns, how fast the transcriber settles, the turn-end threshold in real rooms, Bluetooth routing, and the voices on a phone. A turn sent while an earlier one is still running (`prompt.submit` queued) would hear the earlier reply first.
