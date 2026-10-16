# Mention tags and the mention peek

A sent bubble shows each `@handle` or `@title-slug` token that names a mentionable bot as an inline tag. Tapping a tag peeks at that bot and at what the mention caused, without leaving the chat, and lets the user pull up that bot's live chat on top. Nothing navigates the main window away, and there is no bare "Open Chat" button.

## Tag (unchanged from #33)

- White-translucent capsule (sheen, 1 pt white hairline) holding the bot's 16 pt avatar (`ImageRenderer` snapshot, scaled with Dynamic Type) and the semibold token as typed; narrow no-break spaces keep it on one line. The bubble's gradient is fixed, so the capsule is the same in light and dark (checked in both renders).
- Mentionable: the roster minus the current bot in a bot chat, the members in a group room, the roster minus that bot in the inspector's conversation viewer.
- The token is a link (`crew-mention:<index>`), so VoiceOver's Links rotor and UI tests reach it; a clear overlay over the whole capsule (avatar included) takes touch and pointer taps. Mac: link cursor; iPad: hover highlight.
- Long press on the bubble still opens Copy, Select, Share, also when it starts on a tag.

## The peek

The same content on every platform. It observes the current chat's `ChatSession` transcript, so Sending, Waiting and the reply update in place while it is open.

1. **Header:** 44 pt avatar with live mood, title, `@handle`, and the target's live status from `BotStore` (its own `session.active_list` entry, not the sender's): "Working" (plus its status text when its chat session is open), "Needs approval", "Waiting for you", "Failed", or, for a plain mention, "Active <relative time>" when idle (an exchange card already carries its own times).
2. **The mention card**, a tappable rounded panel with a chevron that brings up the bot's live chat (below). It carries the information, so the tap target is never bare navigation:
   - **Message to <bot>:** the `message` argument of the mentioning turn's `message_agent` call whose `target` is this bot, quoted (what the current bot actually sent, not the user's text).
   - **<Bot>'s reply** with its time: the `Message from … (@handle)` row paired the way #32 pairs them (each queued call with a `process_id` in a user-started turn consumes the next such row from that handle, oldest call first), so an older tag never picks up a newer reply.
   - **No reply yet:** "Waiting for <bot>" with a pulsing dot while the target is working, "No reply yet" when it is idle (also when the history window doesn't hold the reply).
   - **Delivered:** the delivery notice for the call's `process_id` arrived without a reply row (the target answered in its own chat): "Delivered. The answer is in <bot>'s chat."
   - **Sending:** the call is still streaming (the result follows within a second): "Sending…".
   - **Not delivered:** the call errored, or its result has neither a `process_id` nor a queued status: "Not delivered" in red with the server's short reason when there is one.
   - **Relayed:** queued without a `process_id` (another machine through Hermes Desktop): "Sent through Hermes Desktop. The reply will show up there."
   - **Plain mention** (no `message_agent` call to this bot in that turn, group rooms, the conversation viewer): "Recent" with the bot's latest chat preview and its time from the roster, so the peek is never empty.
   - Quotes clamp to 4 lines; the full text is in the live chat.
3. **About:** the bot's description when it has one (up to 3 lines).

The sender's chat still shows its own relay line ("@scout replied: …"); the peek's quote is the target's own words, read from the hidden row, never shown in the transcript.

## iPhone and iPad

- A sheet over the current chat with `.medium` and `.large` detents (driven by `presentationDetents(_:selection:)`), a visible grabber, and `.presentationContentInteraction(.scrolls)` so scrolling the peek or the chat never resizes the sheet by accident. It opens at medium with the peek.
- Dragging to large, or tapping the mention card, grows the sheet and swaps its content to that bot's live chat (the same `ChatScreen` as the bot list opens, fully usable: persona pill title, transcript at the bottom, composer, approvals, inspector push) with a close button that dismisses the whole sheet. Dragging the grabber down from large returns to the peek at medium (a drag on the transcript scrolls it); dragging down from medium dismisses back to the original chat, which never moved.
- On iPad's regular width the sheet is a form sheet; the mention card is the way into the chat there.
- Accessibility: a "Show Chat" accessibility action on the peek, and the grabber is adjustable.
- A tag inside the sheet's chat opens its own peek on top.

## Mac

- A popover anchored at the tapped tag with the same peek, 320 pt wide.
- Clicking the mention card closes the popover and opens that bot's chat in its own window (`WindowGroup(for: Bot.ID)` plus `openWindow`, one window per bot, Cmd-W closes it). The main window keeps its selection and stays usable next to it, like a Mail message opened in its own window. Its persona pill opens that bot's inspector in the window. Rejected: a modal sheet (it would block reading the sender's chat) and swapping the inspector column (it belongs to the selected bot and is too narrow for a chat).

## Every direction and other surfaces

- **Sender's chat:** only the peek is new; its rows are unchanged.
- **Target's chat** in the sheet or window: unchanged (#32's collapsed exchange row once it lands). It marks the target seen like any open chat (`ChatScreen` does it on every new position), so its unread badge clears.
- **Bot list:** keeps its selection; unread clears as above. **Push:** unchanged; foreground banners for the bot in the sheet or window are not suppressed (`PushCenter.show` tracks only the main selection), a known gap. **Inspector:** unchanged.

## States

- Unknown handle or roster not loaded: plain text, no tag.
- Same bot twice in one bubble: each tag opens its own peek over the same turn's call.
- Offline: the peek renders from loaded rows; the live chat shows its usual offline line.
- Bot deleted while the peek is open: the tag stops matching and the peek closes; an open sheet chat or window shows its last state.
- Large Dynamic Type: the peek scrolls inside the medium detent.
- Light and dark: system materials and secondary styles.

## Tests

- Unit tests on the recorded `bot-mention` scenario (Message and Reply from the real rows) and hand-built rows for Sending, Waiting, Delivered, Not delivered, Relayed, the plain mention, `@hermes` and two turns mentioning the same bot.
- UI test (iPhone simulator): tapping the tag opens the sheet with the message and the reply, and the original chat stays underneath.
- Renders: the peek at medium and the live chat at large (iPhone, light and dark). The Mac popover and window are not rendered (no Mac window driving).

## Not in scope

- Opening the target's chat scrolled to the exchange row: on main that row is hidden until #32 lands; the chat opens at the bottom, where the exchange usually is.
- A "Mention" button or a reply field in the peek: the live chat is where you write.
- The group room peek pointing at the member's turn in the room.
