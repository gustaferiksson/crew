# Siri and Shortcuts: Ask a bot, open a bot's chat

"Hey Siri, ask Ada in Crew" asks for the message, sends it to Ada's Bot Chat and speaks Ada's answer, without opening Crew. "Open Ada in Crew" opens Ada's chat. Both are also Shortcuts actions and App Shortcuts in Spotlight. Model: Apple's own App Intents pattern (Reminders' "Add a reminder", Notes' "Open note"), speaking the answer and staying out of the app. Unlike Messages ("Ready to send?"), Ask sends without a confirmation step: it is a deliberate low-risk choice, because the message only goes to the user's own bot, Siri has just read the message back as the parameter, and a confirmation in a sceneless background run is unreliable (PLAN.md, `alwaysConfirm`). iPhone and iPad only.

## Pieces (Apple's documented APIs only)

- `AskBotIntent` (`AppIntent`): parameters `bot` (`BotEntity`) and `message` (String, `requestValueDialog` "What do you want to ask?"). `supportedModes = [.background]` (not the deprecated `openAppWhenRun`), `authenticationPolicy = .requiresAuthentication`. Returns `ReturnsValue<String> & ProvidesDialog`: Siri speaks and shows the dialog, Shortcuts gets the String.
- `OpenBotChatIntent` (`OpenIntent`, `target: BotEntity`, app target only): returns `.result(opensIntent: OpenURLIntent(crew://chat/<profile>))`, the deep link the Live Activity already uses (`PushRoute(url:)` in `BotsView.onOpenURL`), so no new routing plumbing. As an `OpenIntent` the system brings Crew forward and it is what Spotlight runs when a bot is tapped there; if the system declines a non-universal link, Crew still comes forward on its last screen.
- `CrewShortcuts` (the app's one `AppShortcutsProvider`) gains "Ask \(\.$bot) in \(.applicationName)", "Ask a bot in \(.applicationName)", "Open \(\.$target) in \(.applicationName)" and "Open a bot in \(.applicationName)" (the parameterless ones work before bot names are indexed; Siri then asks "Which bot?") (Apple requires the app name in every phrase; only entity parameters can sit in a phrase, so the message is asked for). `BotStore.saveCache()` calls `CrewShortcuts.updateAppShortcutParameters()` after writing `voice-bots.json`, so new and renamed bots become phrases.
- `BotEntity` becomes an `IndexedEntity`: after each cache write Crew replaces its bots in Spotlight (`deleteAppEntities(ofType:)` then `indexAppEntities`), hidden bots left out, so a removed bot disappears from Spotlight too.
- Sign out (`BotStore.reset`) also deletes `voice-bots.json` and the App Group avatars, removes the bots from Spotlight and updates the App Shortcut parameters, so no bot of a signed-out account stays in Siri, Spotlight or the Talk to Bot picker.
- The answer: connect a short-lived gateway from the Keychain session (`restoredURLSession`, `connectedGateway`), `openBotChat` (the same Bot Chat the chat screen resolves or creates), subscribe to `gateway.events()`, then `prompt.submit`, then wait for that runtime session's `message.complete` or `error`. One deadline of 20 s covers the whole run (connect, open, submit, wait) because iOS gives a background intent 30 s.
- Spoken text: the reply goes through the cleaner the push preview and bot list use in spirit: A2UI cards (`<a2ui-json>` and ```` ```a2ui ```` fences) and code blocks are dropped, markdown is rendered to plain text (headings, list items and paragraphs keep their words, one per line). The same text is the String result.

## Surfaces

- **Siri (voice):** "Ask Ada in Crew" → Siri: "What do you want to ask?" → user speaks → Siri shows and speaks Ada's answer. No Crew UI appears. If the phone is locked, Siri asks to unlock (Face ID or passcode) first.
- **Siri, a bot whose name Siri can't match:** Siri offers the bot list from `suggestedEntities` (non-hidden bots).
- **Shortcuts app:** "Ask Bot" action with the summary "Ask <Bot> <Message>"; its output is the answer text, usable in the next action. "Open Bot Chat" action. Both also appear under Crew's App Shortcuts.
- **Spotlight:** App Shortcuts appear when searching "Crew" or a bot's name; bots themselves are indexed and tapping one opens its chat.
- **Crew, that bot's chat (iPhone and Mac):** the message is a normal prompt in the bot's Bot Chat and the reply a normal reply, so the transcript, preview, time and unread on the bot list behave as for a typed message; another device signed in shows it through its usual sync.
- **Push and unread:** when Ask returns an answer in time, crew-push still sends its usual reply notification and the bot stays unread on the bot list: the server can't know Siri spoke it, and marking it read from the intent would hide a reply the user may only have half heard. When Ask times out, that notification is how the answer arrives.
- **Mac:** unchanged. The intents, the bot cache and the App Group are iOS-only (adding the App Group to the Mac changes its provisioning).
- **Light/dark:** no custom UI; Siri and Shortcuts draw the dialog.

## States

- **Answer in time:** the dialog is the first paragraph of the cleaned answer (HIG: keep Siri dialogs brief); a longer answer adds "The rest is in Crew.". The String value is the whole cleaned answer, and the full reply is in Crew.
- **Bot busy with another turn:** `prompt.submit` answers `queued` (or `steered`/`redirected`) instead of `streaming`; Crew doesn't wait (the next `message.complete` would be the other turn's) and answers "Sent. You'll get a notification when <Bot> replies."
- **Answer is only a card (A2UI) or code:** nothing speakable is left, so the dialog is "<Bot> sent a card. Open Crew to see it." and the value is empty.
- **Deadline (20 s) passes:** the gateway disconnects, the turn keeps running on the server (a detached turn finishes and pushes, as the Action button voice message relies on), and the dialog is "Sent. You'll get a notification when <Bot> replies."; the value is empty.
- **Turn fails on the server** (`message.complete` with a status other than complete, or an `error` event): the message was delivered, so nothing goes to drafts; the intent fails with the server's error text, else "<Bot> couldn't answer.".
- **Signed out:** fails with "Sign in to Crew first." (no foreground mode, so Crew isn't opened; the user knows what to do).
- **No bots cached yet** (never opened after install): Siri can't resolve a bot; the query returns none and Siri says it found nothing. Opening Crew once fixes it.
- **Offline, server unreachable, or the submit fails:** nothing was sent; the message is appended on a new line to that bot's composer draft (an existing draft is kept, as the Action button voice message does) and the intent fails with "Couldn't send. It's saved as a draft."
- **Locked phone:** `.requiresAuthentication` makes the system ask for Face ID or the passcode before `perform` runs; without it nothing is sent. Safe default, because Ask sends as the user and shows the answer.
- **Empty message:** Siri asks for the message again (a required String parameter).
- **Hidden bot:** not suggested and not a phrase (phrases come from `suggestedEntities`), but a Shortcuts pick or an answer to Siri's "Which bot?" still works (`entities(for:)` covers hidden bots).
- **Bot deleted since the cache was written:** `openBotChat` fails → treated as a send failure (draft kept, error shown).
- **Open chat, Crew not running / in background / in front:** Crew comes forward on that bot's chat through `onOpenURL`, the same path as tapping the voice Live Activity.

## Verification

- Unit (`BotAnswerTests`, CrewTests): the busy case (a `queued` submit doesn't wait), the reply wait replayed from recorded gateway events in `Tests/fixtures`: complete (`chat.first-turn.v0.22.4.jsonl` → "hi"), timeout (the same stream without its `message.complete`, never finishing → pending), failed turn (`chat.interrupt-turn.v0.21.7.jsonl`, the only recorded non-complete turn: `status: interrupted`), and events of another session ignored. The cleaner: markdown, an `<a2ui-json>` card and a fenced card.
- Real server: `Tests/chat_probe/run.sh ask` runs the same function on `crew-test` and prints the answer and the elapsed time.
- Build: the App Intents metadata (`Metadata.appintents`) lists both intents, all four phrases and `requiresAuthentication` on Ask, with no extractor warnings. Running "Open <bot>" needs the Shortcuts or Siri UI, which can't be driven headless; the `crew://chat/<profile>` route itself is the one the Live Activity already uses (`theLiveActivityLinkOpensThatBotsChat`).
- Sign-out cleanup and the draft append are iOS-only code (the unit tests run on macOS): checked by reading and on the private simulator's build only.
- Not verifiable off-device: Siri voice invocation, the Face ID gate and Siri's real wait. Ships for checking through a tagged release.
