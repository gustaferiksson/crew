# Mention tags and the bot card

A sent bubble shows each `@handle` or `@title-slug` token that names a mentionable bot as an inline tag. Tapping a tag opens a small card for that bot without leaving the chat.

## Surfaces

- **Sent bubble (iPhone, iPad, Mac):** the token renders inline as a white-translucent capsule (light-to-darker sheen, 1 pt white hairline) holding the bot's 16 pt avatar (scaled with Dynamic Type, centred on the text) and the semibold token as typed. Narrow no-break spaces keep avatar and token together, so the tag wraps as one unit. The bubble gradient is fixed, so the capsule reads the same in light and dark; only the avatar follows the appearance.
- **Mentionable bots:** in a bot chat, the roster minus the current bot (so `@hermes` in Hermes's chat stays plain text); in a group room, the room's members only; in the inspector's conversation viewer, the roster minus that bot.
- **Tap anywhere on the tag (avatar or text):** opens the card. On Mac and iPad it is a popover with its arrow on the tapped tag; on iPhone the popover adapts to a sheet sized to the card's height with a drag indicator (Messages and Slack peek at a contact or profile the same way). The chat stays put underneath, and the popover follows the tag if the transcript moves.
- **Pointer:** a link cursor on Mac and a highlight hover effect on iPad.
- **Card:** 64 pt avatar with its live mood, title (up to 2 lines), `@handle`, a status line only when the bot is working, waiting or failed (same words as the bot list), the description (up to 4 lines, hidden when empty), and a prominent "Open Chat" button. Open Chat closes the card and selects that bot exactly like picking it in the bot list (from a room it leaves the room). The conversation viewer has no navigation, so its card has no Open Chat.
- **Long press on the bubble (iPhone):** unchanged Copy, Select, Share menu, also when the press starts on a tag; Copy copies the raw text including the `@handle`.
- **Mac:** a click on a tag opens the card instead of starting a selection; selecting and copying the rest of the text is unchanged. Use the bubble's context menu for an exact copy of the raw text.
- **VoiceOver:** the text reads as written; each tag adds a "Show <bot>" custom action that opens the card. The overlay buttons are hidden from accessibility so nothing is read twice.
- **Composer, bot list, push, inspector tabs:** untouched. The composer text stays plain and no chip row shows.

## Directions

- Only the user's own sent bubbles carry tags. Bot replies and bot-to-bot notices are unchanged.

## States

- **Unknown handle, or roster not loaded yet:** plain text, no tag, not tappable.
- **Same bot twice:** each tag anchors its own popover.
- **Bot deleted or renamed later:** the token no longer matches and renders as plain text.
- **No photo:** the avatar is the generated shape; a photo replaces it once loaded. The inline avatar is a still snapshot (idle mood); the card shows the live mood.
- **Long content:** a folded bubble (Show more) keeps tags tappable in its visible lines only. A tag forced across two lines opens from its first part.
- **Offline:** the card still opens from the cached roster; Open Chat navigates and the chat shows its usual offline state.
- **Composer bar grows** (mention picker, approval card) while the transcript is at the bottom: the transcript stays pinned to the bottom, so the last reply never sits under the bar.

## Not in scope

- A "Mention" button on the card: the draft lives in `ChatView` and the composer focus in `Composer`, so it needs new plumbing; Open Chat is the single action, like Slack and Messages.
