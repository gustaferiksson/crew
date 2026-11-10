# Avatar play

The living avatars (`docs/flows/living-avatars.md`) react when you interact with them. Still only the eyes move, never the body, and nothing turns cartoon: the taste is Memoji and the Dynamic Island, a glance or a startled blink.

## Eyes follow you

- **Mac (and iPad with a pointer):** while the pointer is over an avatar's square frame (the body plus its margin, so "near" the face too), its eyes glance toward the pointer, and ease back to the state's pose in 0.4 s when the pointer leaves. Surfaces: bot list rows, search result rows, sidebar strip tiles, favourite tiles, the chat persona pill (bot chats and conversations) and the inspector header avatar. Everywhere else (work log chips, room members, mention tags, pickers) stays as today.
- **iPhone:** while a finger is down on one of those avatars, before the tap completes, the eyes look at the touch point; they look back when the finger lifts or the touch moves into a scroll. The tap itself does what it did (open the chat, open the inspector).
- **Gaze:** the pointer's offset from the avatar's centre, as a fraction of its size, sets the eye pair's gaze: full reach (0.06 across, 0.04 up or down, like reading's 0.04 but a little further) once the pointer is a quarter of the avatar from its centre, proportional inside that, so a pointer right on the face looks straight out. The glance replaces only the gaze of whatever pose the state is in, so blinks, the wide waiting eyes and the sleepy lids carry on while the bot looks at you. Pure function `EyePose.glance(at:size:)`.

## Poke

- **Trigger, both platforms: double-tap (double-click on the Mac) on the big avatar at the top of the bot inspector (iPhone profile page, Mac inspector).** A single tap on that avatar already opens the Look editor, and the pill's single tap opens (on the Mac, toggles) the inspector, so a single tap can't also poke. A double-tap on the pill would open the inspector on the first tap (and on the Mac close it again on the second), and making the pill wait to tell one tap from two would slow its everyday action. On the header avatar the wait lands on the rarely used Look tap, the way Photos waits to tell a single tap (show or hide the bars) from a double tap (zoom). So: header avatar, double-tap pokes, single tap still opens Look after the system double-tap interval.
- **One poke:** a startled blink: lids snap shut in 0.05 s, then the eyes spring open 30 % larger and slightly past full (`EyePose.startled`) for 0.45 s, then ease back to the state's resting pose (wide when waiting, sleepy when dormant, rest otherwise). A light impact `.sensoryFeedback` on iPhone (silent on the Mac, as every haptic in `docs/flows/haptics.md`).
- **Grumpy:** the third poke within 2 s: lids drop to 38 % and the eyes look sideways and a touch down (`EyePose.grumpy`: gaze +0.06, +0.02, a little wider) for 2.2 s, then back to the mood's resting pose and its normal rhythm. It is lower and sideways, so it never reads as the failed squint (22 %, centred), the sleepy lids (50 %, centred) or the happy blink (45 %, lifted). The count starts over after a grumpy, so the next quick three make it grumpy again. Tilt was not used: the living-avatars spec found tilted eyes read as confused.
- A poke restarts the avatar's one `.task` with the poke steps as its prelude, then the mood's normal cycle (`AvatarMood.reaction(to:)`, `PokeTracker`); no second animation mechanism. Pure and testable: the tracker takes the poke time, the script returns `EyeStep`s.

## When nothing moves

- **Reduce Motion and Low Power Mode:** no gaze following (no glance, the touch and hover handlers do nothing). A poke is one plain blink with no animation: lids shut for 0.18 s, then the still resting pose; never the startle or grumpy. The haptic still plays.
- **Background, inactive window, closed Mac inspector:** no task, no poke steps; the eyes stay at rest as today.
- **Photo avatars:** no eyes, no follow, no poke reaction (the double-tap and haptic still register but nothing moves).
- **Fixtures:** the `inspector-poked` and `inspector-grumpy` snapshot screens freeze the header avatar at the startled and grumpy poses (`avatarFrozenPose`); `avatar-eyes` gains Poked and Grumpy rows on its four looks.

## Accessibility

Decoration only: the avatar stays hidden from VoiceOver. The editable header avatar keeps one element, "Edit Look", a button whose action opens the Look editor, with no new actions. Nothing is announced on a poke.

## States not applicable

Empty, error, offline and long content don't touch the avatar; offline bots can still be poked. No server call, no push, nothing sent to the bot: a poke is local and forgotten when the view goes away.

## Verification

Unit tests drive `PokeTracker` with fixed times (startle, grumpy on the third within 2 s, reset after) and assert the poses, the Reduce Motion blink and the glance mapping, shown failing with the threshold and startle broken. Renders: `./snapshot.sh both inspector-poked inspector-grumpy avatar-eyes`. Live hover on the Mac is not driven by a test (Mac UI tests are disabled); the press gaze and the double-tap are checked on a private iOS simulator.
