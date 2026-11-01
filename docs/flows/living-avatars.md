# Living avatars

A bot's two eyes come alive, quietly, the way Apple gives UI a character (Memoji, the Dynamic Island, the Siri glow): small, rare, physical motion that tells you something, never a cartoon. Only the eyes move. The body keeps its shape, colour, size and position exactly as today.

## What changes from today

- Today a working bot rotates its whole body (a 30 s sway at 15 fps through a `TimelineView`, plus a fixed 5° lean) and a waiting bot swaps to the Curious expression. Both go: the body never moves, and every state is a pose of the bot's own eyes (its own expression stays). PLAN.md's Decisions line "Sidebar faces take their mood from `BotStatus` (working sways, waiting looks curious, failed looks sad)" is updated.
- Today's idle blink (one fixed period per bot, first after 6 s) becomes the idle state below: irregular intervals, still seeded by the bot name so two bots never blink in sync and a test can replay it.
- Failed keeps today's settled Sad expression (the one state that swaps the expression, as today); it gains the squint on entry.
- `AvatarMood` gains `unread` and `dormant`; `BotAvatar` maps `BotStatus` to it (`AvatarMood(status:lastActive:)`, dormant from `bot.canonicalSession?.lastActive`). PLAN.md's `ChatSessions` line ("maps waiting/working/failed to the pill avatar's mood") changes to name the new moods.

## States

Every pose is applied on top of the bot's expression: lid openness scales the eye height, a size factor scales both axes, a tilt adds to each eye's own tilt (mirrored), and the gaze moves the eye pair. Gaze values are fractions of the avatar size in SwiftUI's coordinates (+x right, +y down); a centring factor moves the pair that fraction of the way from the shape's eye anchor toward the body's centre line.

| Status | Pose | Motion |
| --- | --- | --- |
| Idle (read) | Rest, as today | A blink every 3 to 8 s at seeded random intervals (the first one too); about one in six is a double blink. Blink: lids to 12 % in 70 ms, held 110 ms, open in 120 ms (today's timing). |
| Unread | Rest | Same rhythm as idle with plain blinks; the unread dot already says it, so the happy blink plays only on arrival (Transitions). |
| Working | Reading | Eyes read along a line: start on the left (gaze x -0.04), drift right to +0.04 over about 1.1 s (ease in out), snap back left in 0.18 s, next line; after 2 to 4 lines a pause at rest with a blink, 2 to 5 s, so a list of several working bots stays calm next to their Working labels and badges. The first move also waits that pause, so a quick working blip doesn't twitch. |
| Needs approval, question, payment (waiting) | Wide | Eyes turn toward the viewer (centring 0.8, gaze y +0.02, i.e. slightly down toward the face's middle) and open 25 % larger, eased in 0.35 s; held, with idle blinks. |
| Failed | Squint, then Sad | On entering failed: lids to 22 % and eyes 35 % wider (a wince) in 0.12 s, held 0.45 s, then open into the Sad expression (as today), which stays. |
| Dormant (idle and read, last activity 7 days or more ago) | Sleepy | Lids at 50 %, gaze y +0.02 (down); slow blinks (close in 0.25 s) every 8 to 14 s. Any activity wakes it: the next status is a normal state. Bots without a session are never dormant. |

### Transitions (play once, when the avatar sees the change)

- Working or waiting to unread (a reply arrived while you were elsewhere): one happy blink. Not from idle: at launch and after a reset every bot starts idle and then loads its real status, which must not make the whole list blink. Not working to idle: that is also Stop, a denied approval or a dismissed question, and in an open chat the reply itself is the news. Happy blink: a pleased squeeze, lids to 45 %, eyes 30 % wider and lifted 0.045 (more open and higher than the squint, so the two never read alike), in 0.12 s, held 0.35 s, out in 0.2 s (a tilted smile was tried and read as confused on the leaning capsule eyes).
- To failed: the squint above.
- To waiting: the widen above. Waiting to working (approved): eyes ease back and start reading.
- Every other change eases to the new resting pose in 0.35 s (`.smooth`).
- The first status an avatar view sees never greets. Each task start compares the new mood with the last one that view settled on: a view SwiftUI dropped comes back in its new state with no greeting; a view SwiftUI kept (a row under a pushed chat on iPhone, the app back from the background) plays the greeting once when it is on screen again, so the bot that replied while you were away gives its happy blink when you come back. Never twice for one change.

## When nothing moves

Everything settles to the state's resting pose, with no animation:

- **Reduce Motion:** static eyes. Waiting still shows Wide, dormant still Sleepy, failed shows Sad, others Rest; changes between them are instant. No blinks, reading, squint or happy blink.
- **Low Power Mode:** same as Reduce Motion; read when the avatar renders and before each step, so turning it on stills the eyes at the next step and turning it off resumes motion when the avatar next renders or its status changes, with no observer.
- **Off screen:** the motion is a `.task` on the avatar, so a lazy list row, strip tile or favourite tile scrolled away, a list covered by a pushed chat on iPhone, or a closed inspector stops it. Only avatars on screen move.
- **Background or inactive scene:** stopped while `scenePhase` is not `.active` or the window doesn't appear active (`appearsActive`, which on the Mac is false when Crew isn't the frontmost app or the window isn't key), restarted when both are back. A visible Mac window that is key stays live even if partly covered, accepted.
- **Closed Mac inspector:** SwiftUI keeps the hidden inspector's content alive, so `BotInspector` turns its header avatar's motion off while `isPresented` is false (`avatarsAnimate` environment value).
- **Photo avatars:** no eyes, no motion, no task (as today).
- **Rendered images** (`ImageRenderer` in mention tags, the Live Activity, widgets): their first frame, the resting pose; `.task` never runs there.

## Cost

No `TimelineView`, `repeatForever`, `phaseAnimator` or `keyframeAnimator`. One mechanism drives both the ambient rhythm (blink intervals, reading cadence) and the one-shot gestures; `keyframeAnimator` would still need a timer for the rhythm, so it would add a second mechanism for no saving: each visible avatar has one sleeping task that sets an `EyePose` inside `withAnimation` a few times a minute when idle (about one step a second while working). Between steps there is no per-frame work at all; during a step SwiftUI interpolates two eye capsules for 0.1 to 1.1 s. Sleeps carry a 100 ms tolerance so the system can coalesce timers. A hosted test runs a long list of working avatars in an offscreen Mac window with a counting clock (injected through the `avatarClock` environment value) and checks that the step count follows the visible rows plus the list's overscan, not the list length. `CrewTests` is a macOS bundle, so the iOS `List` (collection view) lifecycle is not covered by it; it relies on the same documented `.task` behaviour and is unverified by a test.

## Surfaces

Every surface that shows a bot's status gets it; the rest pass idle (blink only, as today).

- **Bot list rows** (iOS, Mac regular sidebar) and **search result rows:** row size (52 pt iOS, 40 pt Mac).
- **Mac sidebar strip tiles:** 40 pt, under the existing status badge knockout; the badge (and its variable colour effect) is unchanged.
- **iOS favourite tiles:** tile size, unread dot unchanged. The grid sits in one `List` row, so all favourite tiles start and stop together with that row, not per tile.
- **Chat persona pill** (iOS and Mac, 28 pt): status of the open chat, so the reading eyes show while the reply streams and a happy blink when it lands.
- **Inspector header** (96 pt, iOS profile page and Mac inspector): now gets the bot's status from `chats.status(of:in:)` (it passed none before; `.failed` exists only there) and seeds its rhythm from `bot.name`, not the editable name. The look editor's own 120 pt preview stays idle (blink only).
- **Mention peek** (44 pt): already passes status.
- Idle only, unchanged (these pass no status, so they never turn sleepy either; a mention tag image bakes the resting idle eyes): work log and chat mention chips, group members and room avatars, New Bot and New Group sheets, Login, avatar picker previews, voice and Live Activity.
- **Light and dark:** eye colour logic unchanged (contrast against the body colour); poses are geometry only.
- **Small sizes** (16 to 28 pt): the same poses; reading's ±0.04 is about 1 pt at 28 pt, readable but quiet.
- **VoiceOver:** the avatar stays hidden from accessibility; status is already spoken by the row, tile and pill labels. Motion carries no information that isn't also text.

## States not applicable

Empty list, loading, error and offline: an offline list keeps cached statuses, so the eyes follow them (a cached working bot reads until the status refreshes). Long names and long content don't touch the avatar. Push and notifications show no avatar motion. Sender and receiver: the only direction is the bot's status reaching the avatar.

## Fixtures and verification

- `EyePose` and the per-mood step script are pure: unit tests cover each state's poses and timing (blink intervals 3 to 8 s and seeded, reading cadence, wide held, squint then sad, happy blink on unread, sleepy for dormant, static under Reduce Motion), each shown failing against the old code or a broken script.
- Hosted cost test (above).
- A new `avatar-eyes` snapshot screen: each state frozen at its key frame (Idle, Blink, Reading line start, Reading line end, Needs approval, Failed squint, Failed settled, New reply, Long idle) on four looks at 56 pt that cover the worst cases: a teal circle (neutral), a red triangle with Scared eyes (largest eyes on the tightest body, for Wide), a blue squircle with Happy eyes (already narrow, for blinks and the happy blink) and an adaptive hexagon with Wary eyes (asymmetric). Rendered on iOS and Mac, light and dark (`./snapshot.sh both avatar-eyes`), plus `sidebar` (rows) and on the Mac `sidebar-compact` (strip tiles, eye travel against the badge knockout).
