# Mention tags and the mention peek

A sent bubble shows each `@handle` or `@title-slug` token that names a mentionable bot as an inline tag. Tapping a tag peeks at that bot and at what the mention caused, without leaving the chat, and lets the user pull up that bot's live chat on top. Nothing navigates the main window away, and there is no bare "Open Chat" button.

## Tag

- Reads "@ (avatar) Name": a plain "@", then a white-translucent capsule (sheen, 1 pt white hairline) holding the bot's 16 pt avatar (`ImageRenderer` snapshot, scaled with Dynamic Type) and its display title in semibold. The name is `Bot.title` (profile title, then display name, then the profile name, "Hermes" for `default`), read live, so past bubbles follow a rename. The typed token (`@scout`, `@ada-lovelace`) never shows in a bubble; the composer keeps the plain `@handle` text that is sent. A narrow no-break space sets the "@" right against the capsule and keeps it on the capsule's line, and no-break spaces keep a multi-word title in one capsule, so a tag at a line end moves to the next line whole; a title wider than the line breaks inside it and draws one capsule per line fragment. The bubble's gradient is fixed, so the capsule is the same in light and dark (checked in both renders).
- Why: Messages and Mail turn a mention into the person's name, not their handle, and the user asked to keep the "@" as the cue that this is a mention. Keeping the "@" outside the capsule leaves the capsule as just the bot (avatar and name, like a contact token) and keeps the line lighter; the alternative with the "@" inside the capsule was rendered next to it (both renders in the PR). The old avatar plus `@handle` is gone: handles are server ids, the title is what the user knows the bot by.
- Copy, Share and Select (the bubble's menu) give the typed text with its `@handle`s; Mac's in-place text selection copies what it shows ("@ Scout"). Bot list previews, push and the composer keep the typed text, a known difference.
- Accessibility: the title is the link (VoiceOver reads "at", then "Scout, link"); two bots with the same title are told apart only by avatar, a known gap.
- Nothing else draws a tag: the peek header (avatar, title, `@handle` as the secondary line, like a contact card), the picker rows ("Scout @scout") and the plain composer stay as they are.
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
   - **Delivered:** the delivery notice for the call's `process_id` arrived, succeeded, and no reply row followed (the target answered in its own chat): "Delivered. The answer is in <bot>'s chat." A notice that failed or left the outcome open is Not delivered (see `delivery-failure.md`).
   - **Sending:** the call is still streaming (the result follows within a second): "Sending…".
   - **Not delivered:** the call errored, its result has neither a `process_id` nor a queued status, or its delivery notice failed: a red headline and the plain-language reason from `delivery-failure.md` (else the server's short error when it is one plain line); an unconfirmed outcome reads "Delivery to <bot> couldn't be confirmed." in secondary text.
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
- **Bot list:** keeps its selection; unread clears as above. **Push:** unchanged on iPhone and iPad (banners for the bot in the sheet are not suppressed, a known gap); on Mac the chat window reports its bot when it becomes key, so its banners are hidden like the main selection's (`docs/flows/mac-chat-window.md`). **Inspector:** unchanged.

## States

- Unknown handle or roster not loaded: plain text, no tag.
- Same bot twice in one bubble: each tag opens its own peek over the same turn's call.
- Offline: the peek renders from loaded rows; the live chat shows its usual offline line.
- Bot deleted while the peek is open: the tag stops matching and the peek closes; an open sheet chat or window shows its last state.
- Large Dynamic Type: the peek scrolls inside the medium detent.
- Light and dark: system materials and secondary styles.

## Tests

- Unit tests on the recorded `bot-mention` scenario (Message and Reply from the real rows) and hand-built rows for Sending, Waiting, Delivered, Not delivered, Relayed, the plain mention, `@hermes` and two turns mentioning the same bot.
- UI test (iPhone simulator): the tag's link reads the bot's title; tapping it opens the sheet with the message and the reply, and the original chat stays underneath.
- Renders: the tag in the bubble (one wrapped at a line end, a two-word title), both tag variants, the peek at medium and the live chat at large (iPhone, light and dark). The Mac popover and window are not rendered (no Mac window driving).

## Performance

Typing in the composer, typing `@` with the picker open, scrolling a long chat full of tags and opening the peek stay smooth on a long chat (the `-mentionTurns` fixture, profiled with Time Profiler). A bubble resolves its tags once per body, never from the tap overlay that reruns on every scroll frame; avatar snapshots render once per bot, size and appearance. `MentionPerformanceTests` keeps tag resolution and the peek's exchange lookup on a 600-turn chat inside a budget. Before and after numbers are in the PR.

## Not in scope

- Right-to-left bubbles: the "@" follows the system's bidi rules; not rendered.
- Group room and inspector conversation bubbles: the same `UserBubble`, not rendered separately.
- Opening the target's chat scrolled to the exchange row: on main that row is hidden until #32 lands; the chat opens at the bottom, where the exchange usually is.
- A "Mention" button or a reply field in the peek: the live chat is where you write.
- The group room peek pointing at the member's turn in the room.
