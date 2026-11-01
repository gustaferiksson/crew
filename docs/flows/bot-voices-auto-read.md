# Bot voices: auto-read and Now Playing (#118, layer 2)

Builds on `docs/flows/bot-voices.md` (v1: Speak in the reply menu, a voice per bot). Layer 2 adds a per-bot "Read Replies Aloud" toggle and system playback controls for anything Crew speaks.

What Apple does: Messages' "Announce Messages" reads incoming messages only in a context the user chose and never during a call; spoken-word apps (Podcasts, Books) take the audio session, pause music, and show Now Playing on the Lock Screen and in Control Center with play/pause. Crew follows those.

## Surfaces

| Surface | Behaviour |
| --- | --- |
| Bot inspector, Voice section | A "Read Replies Aloud" switch under the voice picker, off by default. Footer adds "New replies are read aloud while this chat is open." Stored per bot on this device, next to the voice (`UserDefaults` `botReadAloud`, a list of profile names). |
| Bot chat, a reply finishes | When the last turn goes from streaming to complete while this chat is on screen, and that same turn also started streaming while the chat was on screen, and the bot has Read Replies Aloud on, Crew speaks it exactly like Speak in the menu (same text, same voice, menu shows Stop Speaking). Interrupted, failed and empty or card-only replies are not read. |
| Bot chat, opening it | Nothing is read: a reply that finished before the chat was on screen stays silent, including one that the first load or a reconnect replay (`message.complete` replayed by `ChatSession.load`) flips from streaming to complete, because its streaming did not start while the chat was on screen. The trigger is an `onChange` in `ChatView`, never code in `ChatSession`. |
| Queued prompt | A queued prompt is submitted right after the reply completes; that does not stop the reading (the user asked for both). The next reply finishing replaces it. |
| Group chat | Not auto-read in this layer (a room can have several bots answering at once); Speak in the menu still works. |
| Lock Screen, Control Center, Dynamic Island media controls, Mac Now Playing menu | While Crew speaks (Speak, auto-read or Play Sample): title is the bot's name, subtitle is the start of the reply. Pause, Play (resume), Play/Pause toggle and Stop. Pause and resume set `MPNowPlayingInfoPropertyPlaybackRate` to 0 and 1 (iPhone reads the rate) and `playbackState` (Mac). The remote command handlers are added when speech starts and removed when it stops, and Now Playing is cleared then. |
| Reply menu while paused | Still "Stop Speaking" on the paused reply; Speak on another reply replaces the paused one. |
| Bot list, push, unread | Unchanged. Auto-read does not mark anything read or change push; a reply read aloud while the chat is open is already seen. |

## When auto-read speaks

All must hold at the moment the reply completes:

- The chat is on screen: its view has appeared and not disappeared (a pushed inspector page or switching bots counts as gone), and the scene is active (`scenePhase == .active`; on Mac the window also `appearsActive`, so a chat in a background window stays silent).
- The microphone is not recording (`Speaker.isRecording`, set by `Dictation`, covers the composer and the Action button voice message).
- No phone or FaceTime call is in progress (iPhone: `CXCallObserver` has a call that has not ended; Mac has no call check, a FaceTime call there takes the audio). An audio interruption during speech stops it, as in v1.
- The bot has Read Replies Aloud on.

Once speaking, it carries on if the iPhone locks or Crew goes to the background (background audio mode), with Lock Screen controls, like a podcast. Leaving the chat, sending, dictating and Start New Chat stop it, as in v1. A new reply finishing replaces the one being read.

## Audio session (iPhone)

Now Playing and remote commands only go to the app that owns a non-mixable session, so speech now uses `.playback`, mode `.spokenAudio`, no options (v1 used `.duckOthers` + `.interruptSpokenAudioAndMixWithOthers`). Music and podcasts pause while Crew speaks, as they do for Podcasts and Books, and resume when Crew deactivates with `.notifyOthersOnDeactivation` after speech ends or stops. Paused keeps the session active (other audio stays paused) until Play or Stop. Headphones or AirPods disconnecting (`routeChangeNotification` with `.oldDeviceUnavailable`) pauses, like every playback app, so the reply doesn't continue out of the speaker. `AVSpeechSynthesizer.usesApplicationAudioSession` stays true (the default), so speech uses this session. Play Sample uses the same session, so it pauses music too, like any spoken audio. Mac has no session; Now Playing uses `playbackState` there.

## States

- Empty: a reply with no speakable text is not read; Now Playing never shows an empty item.
- Error: a failed or interrupted turn is not read. A failed session activation leaves the reply unread and silent.
- Offline: nothing new completes while offline; a reply that completes on reconnect while the chat is open is read.
- Long content: one utterance; Pause and Stop work from the Lock Screen at any point.
- Dictating, recording or on a call: silent, nothing queued for later.
- Locked or in the background when a reply finishes: silent (the chat is not on screen); speech already playing continues.
- Light and dark: a system switch only.
- Known gap: on iPhone the mention sheet covers the chat without it disappearing, so a reply finishing behind that sheet is read.

## Not in this layer

Group chat auto-read, Personal Voice, server voices, reading replies for chats not on screen (CarPlay, AirPods announce), highlighting spoken words.

## Verification

- `BotVoiceTests` on a silent synthesizer and no Now Playing center: auto-read speaks only with the toggle on and only a complete reply, not while recording, not on a call; pause and resume change state; stop clears; the toggle persists in a test suite domain. Each shown failing without its guard.
- The on-screen rule (appeared, active scene, active window, streamed while on screen) is a view condition in `ChatView`, and the call and route-change checks are iPhone-only APIs the macOS test bundle can't reach; all checked by review; tests can't host a window offscreen with a real scene phase.
- Renders of the Voice section with the switch, iOS and Mac, light and dark. Lock Screen and Control Center are system UI that can't be rendered, and the PR flags them as unverified on a device; not heard on a device (dev builds are never installed), so checked on the next release.
- No real-server probe: speech is local and the reply arrives through the existing `message.complete` path.
