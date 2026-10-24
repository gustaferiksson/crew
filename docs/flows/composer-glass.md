# Composer field glass like Messages

The message field draws an 85% background fill under its `.glassEffect`, so on iPhone and Mac it reads as an almost opaque white (or black) capsule. Messages on iOS 27 and macOS 27 draws the field as clear Liquid Glass and keeps text behind the bar legible with the soft bottom scroll edge effect. User decision: follow iMessage as closely as possible.

## Why the fill existed

Both pieces landed in 0.1.0 (e492971). The transcript's bottom scroll edge effect was hidden (`.scrollEdgeEffectHidden(true, for: .bottom)` in `ChatView`) because the hard style drew an opaque band and a divider over the transcript. With no edge effect, text scrolling under the bar showed straight through the clear glass, so the field got a background fill to turn it into a faint tint (PLAN.md Decisions). The fill made up for the missing edge effect.

## The change

- `ChatView`: the transcript uses the soft scroll edge effect on both vertical edges (`.scrollEdgeEffectStyle(.soft, for: .vertical)`), replacing `.scrollEdgeEffectHidden(true, for: .bottom)`. Soft is the blur and fade Messages uses under its input bar, not the hard band that caused the 0.1.0 decision. On iOS, deleting the hide alone would give the automatic (soft) style; the explicit `.soft` is deliberate so macOS, where automatic can resolve to hard, gets the same soft edge. The Mac scrolled render (`search-result`) is the gate for that override. The top edge is unchanged (already soft).
- `Composer`: the `.background(.background.opacity(0.85), in: .rect(cornerRadius: fieldHeight / 2))` line is deleted (not lowered); the field keeps its `.glassEffect(.regular.interactive(), in: .rect(cornerRadius: fieldHeight / 2))`, the same clear glass as the `+` circle beside it.
- Both changes apply to iOS and macOS alike, since the fill and the hidden edge were shared. macOS Messages' field is clear glass too (no Mac Messages screenshot was supplied; judged from the system field style).
- No locked UI value changes: field height 40/36 pt, bottom offset, 28/16 pt side margins, 32 pt action circle and the jump arrow stay as they are.

## Surfaces

- **Chat, iPhone and Mac, light and dark:** the field is clear glass with the same tint and rim as the `+` circle. Transcript text under the bar is blurred and faded by the edge effect, so the placeholder, the draft and the in-field action stay readable over any content (long Markdown replies, code blocks, tables, images, cards in the transcript).
- **Cards above the composer (approval, question, payment, notice, shop offer):** they sit in the same `safeAreaBar`, so the soft edge covers their height too and the transcript blurs behind them, like Messages' bar with extras above it. The cards keep their own glass.
- **Jump to Latest arrow:** an overlay of the transcript in `TranscriptScroll`, 12 pt above the bar (locked, unchanged), so it now floats over the fade above the bar; its glass reads over blurred content (seen in `search-result`).
- **Group rooms and the Mac chat window:** use `ChatView`, so they get the same.
- **Bot list, bot list preview/time/status/unread, push, inspector:** untouched. Sender and receiver directions are unaffected; nothing about sending, replies or state changes.

## States

- **Empty chat:** the empty state shows above the composer; the field is clear glass over the background.
- **Empty field, typing, multi-line (up to 6 lines):** the field grows upward as clear glass; the blur region grows with the bar.
- **Keyboard up and down (iPhone):** the bar rides the keyboard; the edge effect follows the bar's inset, so the text just above the keyboard is blurred the same way.
- **Text scrolling under the field:** at the end of a long transcript the last turn sits above the bar; scrolled up, content passes under the bar blurred and faded, never as sharp text behind the placeholder.
- **Offline:** the offline line shows above the field, which stays editable as clear glass with the actions disabled.
- **Running, dictation, attachments, mention picker:** unchanged content inside or above the same clear field.
- **Long content in the field:** the field caps at 6 lines and scrolls inside itself as before.
- **Tall card plus keyboard (`HeightCap`):** the bar is capped at the room above the keyboard, so with a payment card up the blurred region can cover most of the visible transcript. Acceptable: the card is modal in intent and Messages has no taller bar to compare with.
- **Nested scroll views in the bar (payment card rows, mention picker):** they inherit the soft style instead of the hidden one; edge effects only draw next to bars, so nothing shows (checked in the payment render).

## PLAN.md

Three Decisions lines describe the old state and are rewritten in this change: the transcript line on the bottom edge effect, the chat column line ("no bottom scroll edge effect") and the transcript line on the field's background fill. No locked UI value changes.

## Other differences from Messages (reported, not changed here)

Measured against the user's iPhone screenshots at the same scale: `+` circle and field size, gap and placeholder inset match. Messages' in-field dictation glyph is a shorter, wider waveform in a lighter grey about 12 pt from the field's trailing edge; Crew's `waveform` glyph is taller and darker and sits about 17 pt in. Messages' placeholder text is slightly smaller. The placeholder wording ("Message <bot>") is ours by design.

## Verification

- `./build.sh`, zero warnings.
- Renders before and after, light and dark, iOS on a private simulator (deleted after) and Mac via `./snapshot.sh`: `chat`, `composer-line`, `composer-lines`, `chat-offline`, `chat-question`, `chat-payment` (tallest card in the bar) and `search-result` (a long transcript scrolled away from the end so text passes under the composer, on both platforms).
- Keyboard up is not rendered (snapshots do not focus the field): the bar and its edge ride the keyboard inset exactly as before, and only the drawing behind the field changed.
- No new unit test: nothing about behaviour changes, only drawing, which the renders check. An independent reviewer compares the renders with the Messages reference.
