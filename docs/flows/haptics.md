# Haptics (#104)

Haptics confirm what the user did and mark state changes they care about, the way Messages, Mail and Wallet do (HIG "Playing haptics"). Every one is a SwiftUI `.sensoryFeedback` at the view that owns the trigger, so the system haptics setting applies and the Mac (no Taptic Engine in most cases) stays silent without Mac code.

| Event | Surface | Feedback | Trigger |
| --- | --- | --- | --- |
| Message, steer or queued message sent | Bot chat, group chat | `.success` | Composer send (`ChatView`) |
| Bot reply finished (chat open) | Bot chat, group chat | `.success` | Last prompted turn goes streaming to complete (`ChatView`) |
| Reply failed (chat open) | Bot chat, group chat | `.error` | Last prompted turn goes streaming to error (`ChatView`) |
| Steer failed | Bot chat | `.error` | `ChatSession.failure` set (`ChatScreen`) |
| Approval, question or payment card appears | Composer bar | `.warning` | New `request.id` (`ChatView`) |
| Allow Once / for Session / Always, question answered or skipped | Approval and question cards | `.success` | Card callback (`ChatView`) |
| Deny | Approval card | `.impact(flexibility: .rigid)` | Card callback (`ChatView`) |
| Hold to Pay press, payment approved | Payment card | light impact, `.success` | Existing (`PaymentCard`) |
| Payment failed | Payment card | `.error` | `PaymentCardState.failure` set (`PaymentCard`) |
| Offline line appears | Composer | `.warning` | Offline phase begins, after the existing 2 s delay (`Composer`) |
| Dictation starts | Composer | `.start` | Existing (`Composer`) |
| Pin / Unpin, Hide / Unhide | Bot list rows (menu and swipe buttons) | `.impact(weight: .light)` | Button tap (`BotsView`) |
| Inspector tab changed | Bot inspector segmented control | `.selection` | `tab` (`BotInspector`) |
| Model changed | Chat model switcher | `.selection` | `ModelSwitcher.current` changes after load (`ChatScreen`) |

## Deliberately silent

- Streamed tokens, tool steps, scrolling and the timestamp swipe: continuous, so no haptic (HIG: don't overuse).
- Toggles, full-swipe thresholds, context menu opening, pull-to-refresh, pickers in menus: the system already plays or omits these; a second haptic would double them.
- Interrupted replies (the user pressed Stop) and routine or agent-message turns with no prompt: the user didn't wait for them.
- Cards already pending when a chat opens, and the first model load: `.sensoryFeedback` fires only on change after the view appears.
- Payment Deny: the card's own buttons, kept as is.

## States

- Offline: the offline line's warning plays once per transition, never while offline continues; send is disabled so no send haptic.
- Error: covered in the table (reply, steer, payment).
- Empty and long content: no haptics; they have no trigger.
- Mac: same modifiers, silent on hardware without haptics; no Mac-specific code.

## Verification

Declarative modifiers with no logic of their own, so no unit tests. `./build.sh` clean on both platforms. Not checked on a real iPhone: dev builds are never installed on the user's devices, so the feel is checked on the next release.
