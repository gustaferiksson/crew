# Bot voices v1 (#118)

Crew reads a bot's reply aloud on request, in a voice chosen per bot. v1 is on-device only (`AVSpeechSynthesizer`): instant, offline, free, works on iPhone and Mac. Hermes server TTS, auto-read, Now Playing and Personal Voice are later layers.

What Apple does: Speak Selection and Speak Screen read text on request with the voice from Settings > Accessibility > Spoken Content, the Mac's Edit > Speech menu offers Start Speaking / Stop Speaking, and per-item settings live in that item's inspector. Crew follows those.

## Surfaces

| Surface | v1 behaviour |
| --- | --- |
| Bot reply, context menu (long press on iPhone, right click on Mac) | "Speak" (`speaker.wave.2`) after Copy/Select/Share. While that reply is speaking the item reads "Stop Speaking" (`stop.fill`). Shown on finished bot replies and agent answers; not on user bubbles, command output, queued prompts or a reply still streaming. Hidden when the reply has nothing speakable (only a code block or a card). |
| Group chat reply | Same menu; the voice is the speaking bot's (`Turn.speaker`), not the room's. |
| Bot inspector, Info tab | A "Voice" section right after Rich UI: a menu `Picker` "Voice" and a "Play Sample" / "Stop" button. |
| Composer (bot chat and group chat) | Sending a message stops speech. Starting dictation stops speech. |
| Action button voice message (`VoiceMessage`) | Starting to record stops speech (it records through `Dictation`, same hook). |
| Start New Chat | Stops speech (the chat it came from is gone). |
| Compact card sheet (#243), command output, work log | No Speak: cards and code are not read aloud. |
| Chat screen | Leaving the chat that is speaking (navigating away, switching bots on Mac, closing a chat window) stops speech, so nothing keeps talking with no visible Stop. A transcript reload keeps the same turn ids, so speech carries on and the menu still shows Stop Speaking. |
| Bot list (preview, time, status, unread), push, sidebar | Unchanged: speaking is not a message event. |
| Group inspector | No voice setting: voices belong to bots; a room uses each member's voice. |

## Speech text

`SpeechText` turns the reply's markdown into what a person would read out, using `markdownBlocks` (the same parse the transcript draws):

- Paragraphs, headings and quotes: their plain text, each ending in a sentence break so the voice pauses.
- List items: their text, one sentence each, without bullets; ordered items keep their number ("1. Test purchase ..."); nested items read the same.
- Code blocks and A2UI cards (`a2uiFenced` turns `<a2ui-json>` into an `a2ui` fence): dropped. A reply that is only code or a card has no speakable text, so Speak is hidden.
- Inline markdown (bold, italics, links, inline code): the visible text only; link URLs are not read.
- Tables: each cell's text as its own sentence.
- Thematic breaks: dropped.

## Speaking

- One `Speaker` for the app, one utterance at a time: Speak on another reply stops the current one and starts the new one; Stop Speaking stops at once.
- iPhone: before speaking, the audio session becomes `.playback` with mode `.spokenAudio` and options `.duckOthers` + `.interruptSpokenAudioAndMixWithOthers` (music ducks, podcasts pause, like Maps directions); it ignores the Silent switch because the user asked for it. `stop()` stops the synthesizer and deactivates the session synchronously (`.notifyOthersOnDeactivation`), so `Dictation.start`, which calls it first, activates `.playAndRecord` only after; a natural finish deactivates from the delegate only when the finished utterance is still the current one, so a late callback for a stopped utterance never touches a session Dictation now owns. Delegate callbacks compare utterance identity, so the first reply's cancel never clears the second. An audio interruption (a call, Siri) stops speech.
- iPhone in the background or locked: speech keeps going (`UIBackgroundModes` already has `audio`); lock-screen controls come with Now Playing in layer 2.
- Mac: no audio session; the synthesizer plays through the default output.
- VoiceOver: utterances use the bot's voice (`prefersAssistiveTechnologySettings` stays false); the menu items have text labels.

## Voice choice

- Stored per bot on this device only (`UserDefaults` key `botVoices`, `[profile: voice identifier]`, like `PushPrefs`): voice identifiers differ per device and between iPhone and Mac, so it never goes to `ui_meta` or the profile config.
- Picker options: "Automatic" first, then installed voices in the user's preferred languages (`Locale.preferredLanguages`), one section per language and region (named like "English (United Kingdom)", the device's own region first), best quality first inside a section (Premium, Enhanced, then default), quality shown after the name ("Ava (Premium)"). Novelty voices and duplicate name/language pairs are left out. Personal Voice is not listed in v1.
- Automatic: the best installed voice for the reply's language (detected on device with `NLLanguageRecognizer`), else for the device language, else the system default.
- A stored voice is used when it is installed, else Automatic. A stored voice that is no longer installed reads as Automatic in the picker and in speech; its stored value is kept so it comes back if the voice is reinstalled.
- The voice list refreshes on `AVSpeechSynthesizer.availableVoicesDidChangeNotification` (a voice downloaded or deleted in Settings while Crew runs).
- Play Sample speaks "Hi, I'm <bot title>. This is how I sound." in the selected voice; it becomes "Stop" while playing. Changing the voice while a sample plays stops it.
- Footer: "Saved on this device. Download more voices in Accessibility settings." (one wording for iPhone, iPad and Mac, and it survives settings renames).
- The section works while offline and while the profile is loading (it is local, unlike the server-backed sections).

## States

- Empty: a reply with no speakable text hides Speak. No installed voice for any preferred language: the picker shows only Automatic and speech uses the system default voice.
- Error: the synthesizer has no failure callback; if speech never starts, the menu returns to "Speak" when the utterance is cancelled or finishes. A failed audio session activation stops and leaves the menu on "Speak".
- Offline: everything works; nothing goes to the server.
- Long content: one utterance for the whole reply; Stop is immediate (`stopSpeaking(at: .immediate)`).
- Deleted or renamed bot: its stored voice entry stays unused (profile names are the key); harmless.
- Light and dark: system controls only.

## Not in v1

Auto-read replies, Now Playing and remote commands (layer 2; that needs a non-mixable session, since a mixable one gets no Now Playing), so while locked or in the background there is no visible Stop until then; server TTS voices, Personal Voice, highlighting the spoken words, hands-free conversation.

## Verification

- `SpeechTextTests` on recorded replies from `Tests/fixtures` (long replies with headings, lists, tables, a code reply, an A2UI recipe), shown failing without the change.
- `BotVoiceTests` for voice ordering and resolution (stored, uninstalled, other language, automatic) on synthetic voice lists, and the store on a test suite domain, never `dev.gustaf.crew`.
- `SpeakerTests`: Speak on a second reply replaces the first, the first utterance's cancel callback does not clear the second, Stop clears, a stale finish callback leaves the session alone, Dictation start and Start New Chat stop.
- No real-server probe: the feature is local only and sends nothing to Hermes.
- Renders: the inspector Voice section on iOS and Mac, light and dark. The context menu is system UI that snapshots can't open; its wording is covered by this spec and review.
